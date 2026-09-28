/// sherpa-onnx 온디바이스 한국어 ASR 로 호출어를 감지한다.
///
/// **전부 기기 안에서 돈다.** 대기 중 클라우드 요청이 0 이라는 검증 기준을 이 구현이
/// 지탱한다.
///
/// 키워드 스포팅 전용 경로도 있으나 사전학습 모델이 영어·중국어뿐이라 쓰지 못한다.
/// 대신 스트리밍 ASR 을 돌리고 전사에서 문구를 찾는다.
///
/// CAUTION: 감지기가 도는 동안 마이크를 점유한다. 전사를 시작하기 전에 [stop] 으로
/// 반드시 놓아야 한다 — 소유권 관리는 `VoiceSessionManager` 가 한다.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'asr_assets.dart';
import 'voice_ports.dart';
import 'wake_phrase.dart';

/// 마이크 표본화율. 모델이 16kHz 로 학습돼 있다.
const _sampleRate = 16000;

class SherpaWakeWordDetector implements WakeWordDetector {
  SherpaWakeWordDetector({
    String phrase = defaultWakePhrase,
    Logger? logger,
    AudioRecorder? recorder,
  })  : _phrase = phrase,
        _logger = logger ?? Logger(printer: SimplePrinter()),
        _recorder = recorder ?? AudioRecorder();

  final String _phrase;
  final Logger _logger;
  final AudioRecorder _recorder;

  final _detections = StreamController<void>.broadcast();
  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  StreamSubscription<Uint8List>? _audio;
  bool _running = false;
  bool _loggedFirstChunk = false;

  /// 호출어 뒤에 이어 말한 내용. 한 번에 말한 경우를 살린다.
  String? trailingUtterance;

  @override
  Stream<void> get detections => _detections.stream;

  @override
  Future<void> start() async {
    if (_running) return;

    // 단계마다 로그를 남긴다. 네이티브에서 죽으면 스택이 안 남아, 마지막으로 찍힌
    // 줄이 어디서 죽었는지 알려주는 유일한 단서가 된다.
    _logger.i('WakeWord: checking permission');
    if (!await _recorder.hasPermission()) {
      throw StateError('microphone permission is not granted');
    }

    _logger.i('WakeWord: creating recognizer');
    _recognizer ??= await _createRecognizer();

    _logger.i('WakeWord: creating stream');
    _stream = _recognizer!.createStream();
    _running = true;

    _logger.i('WakeWord: starting audio capture');
    final audio = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
    );

    _logger.i('WakeWord: subscribing to audio');
    _audio = audio.listen(_onAudio, onError: (Object error) {
      _logger.e('Wake word audio stream failed', error: error);
    });
    _logger.i('Wake word detection started (on-device, phrase="$_phrase")');
  }

  Future<sherpa.OnlineRecognizer> _createRecognizer() async {
    sherpa.initBindings();
    final paths = await prepareAsrModel();
    final config = sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: paths.encoder,
          decoder: paths.decoder,
          joiner: paths.joiner,
        ),
        tokens: paths.tokens,
        numThreads: 1,
        modelType: 'zipformer2',
      ),
      // 문구 하나만 찾으면 되므로 탐색을 넓힐 이유가 없다. 배터리를 아낀다.
      decodingMethod: 'greedy_search',
      enableEndpoint: true,
      rule1MinTrailingSilence: 2.4,
      rule2MinTrailingSilence: 1.2,
      rule3MinUtteranceLength: 20,
    );
    return sherpa.OnlineRecognizer(config);
  }

  void _onAudio(Uint8List bytes) {
    final stream = _stream;
    final recognizer = _recognizer;
    if (!_running || stream == null || recognizer == null) return;

    if (!_loggedFirstChunk) {
      _loggedFirstChunk = true;
      _logger.i('WakeWord: first audio chunk (${bytes.lengthInBytes} bytes)');
    }

    stream.acceptWaveform(samples: _toFloat(bytes), sampleRate: _sampleRate);
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }

    final text = recognizer.getResult(stream).text;
    if (text.isEmpty) return;

    final trailing = matchWakePhrase(text, phrase: _phrase);
    if (trailing == null) {
      // 끝점에 닿으면 버퍼를 비운다. 안 비우면 전사가 계속 길어진다.
      if (recognizer.isEndpoint(stream)) recognizer.reset(stream);
      return;
    }

    _logger.i('Wake word matched in transcript: "$text"');
    trailingUtterance = trailing.isEmpty ? null : trailing;
    recognizer.reset(stream);
    _detections.add(null);
  }

  /// 16비트 PCM 을 엔진이 받는 -1..1 실수로 바꾼다.
  Float32List _toFloat(Uint8List bytes) {
    final samples = bytes.buffer.asInt16List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 2,
    );
    final out = Float32List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      out[i] = samples[i] / 32768.0;
    }
    return out;
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _audio?.cancel();
    _audio = null;
    await _recorder.stop();
    _stream?.free();
    _stream = null;
    _logger.d('Wake word detection stopped, microphone released');
  }

  @override
  Future<void> dispose() async {
    await stop();
    _recognizer?.free();
    _recognizer = null;
    await _recorder.dispose();
    await _detections.close();
  }
}

/// 호출어 감지를 끈 구현.
///
/// 마이크를 잡지 않는다. 기기에서 감지기가 문제를 일으킬 때 원인을 가르는 스위치이자,
/// 배터리를 아끼고 싶을 때의 설정이다. 이때는 마이크 버튼이 주 진입이 된다.
class DisabledWakeWordDetector implements WakeWordDetector {
  final _detections = StreamController<void>.broadcast();

  @override
  Stream<void> get detections => _detections.stream;

  @override
  Future<void> start() async {
    // 조용히 성공한다. 꺼 두기로 한 상태이므로 예외를 던지지 않는다.
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => _detections.close();
}
