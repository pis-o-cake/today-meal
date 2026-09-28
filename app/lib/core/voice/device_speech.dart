/// 기기 내장 전사·낭독.
///
/// CAUTION: 내장 인식 서비스가 항상 기기 안에서 처리되는 것은 아니다. 구현에 따라 외부
/// 서버로 오디오를 보낼 수 있으므로 **완전 오프라인 STT 라고 표현하지 않는다.**
///
/// 호출어 감지도 같은 인식 서비스를 쓰므로 [SpeechEngine] 을 공유한다. 마이크 소유권은
/// `VoiceSessionManager` 가 관리하고, 여기서 다루는 것은 **호출 이후의 짧은 명령**뿐이다.
library;

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:logger/logger.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'speech_engine.dart';
import 'voice_ports.dart';

/// `speech_to_text` 기반 전사기.
class DeviceSpeechTranscriber implements SpeechTranscriber {
  DeviceSpeechTranscriber({required SpeechEngine engine, Logger? logger})
      : _engine = engine,
        _logger = logger ?? Logger(printer: SimplePrinter());

  final SpeechEngine _engine;
  final Logger _logger;

  SpeechToText get _speech => _engine.plugin;

  @override
  Future<bool> isAvailable() => _engine.ensureReady();

  @override
  Future<String> transcribeOnce({
    String localeId = 'ko_KR',
    void Function(String partial)? onPartial,
  }) async {
    if (!await _engine.ensureReady()) {
      throw const TranscriptionException('speech recognizer is unavailable');
    }

    final completer = Completer<String>();
    var latest = '';

    // IMPORTANT: 인식 오류를 보지 않으면 최종 결과를 기다리며 타임아웃까지 버틴다.
    // 실기기에서 error_client 하나에 26초를 허비했다. 오류가 오면 곧바로 끝낸다.
    final errorSub = _engine.errors.listen((error) {
      if (completer.isCompleted) return;
      _logger.w('Transcription aborted by recognizer: $error');
      completer.complete(latest);
    });

    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        partialResults: true,
        cancelOnError: true,
        // 명령이 짧으므로 받아쓰기 모드가 아니라 확정 모드를 쓴다.
        listenMode: ListenMode.confirmation,
        // WARNING: `pauseFor` 는 발화 뒤 침묵만이 아니라 **말을 시작하기까지의 대기**
        // 에도 쓰인다. 2초로 두었더니 사용자가 입을 떼기 전에 error_speech_timeout 으로
        // 끊겼다. 실기기에서 확인한 값이다.
        //
        // 길게 두면 말이 끝난 뒤 기다리는 시간도 함께 길어진다. 4초가 타협점이고,
        // 실제 사용에서 답답하면 줄인다.
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(seconds: 15),
      ),
      onResult: (result) {
        latest = result.recognizedWords;
        onPartial?.call(latest);
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(latest);
        }
      },
    );

    // 최종 결과 없이 인식이 멈추는 기기가 있다. 마지막 중간 결과라도 살린다.
    unawaited(
      Future<void>.delayed(const Duration(seconds: 17)).then((_) {
        if (!completer.isCompleted) completer.complete(latest);
      }),
    );

    final text = await completer.future;
    await errorSub.cancel();
    await _speech.stop();
    if (text.trim().isEmpty) {
      throw const TranscriptionException('no speech recognized');
    }
    return text;
  }

  @override
  Future<void> cancel() => _engine.release();
}

/// `flutter_tts` 기반 낭독기.
class DeviceSpeechSpeaker implements SpeechSpeaker {
  DeviceSpeechSpeaker({FlutterTts? tts, Logger? logger})
      : _tts = tts ?? FlutterTts(),
        _logger = logger ?? Logger(printer: SimplePrinter());

  final FlutterTts _tts;
  final Logger _logger;
  bool _ready = false;

  @override
  Future<bool> isKoreanAvailable() async {
    if (_ready) return true;
    try {
      final available = await _tts.isLanguageAvailable('ko-KR');
      if (available != true) {
        _logger.w('Korean TTS voice is not installed on this device');
        return false;
      }
      await _tts.setLanguage('ko-KR');
      await _tts.setSpeechRate(0.5);
      await _tts.awaitSpeakCompletion(true);
      _ready = true;
      return true;
    } catch (error) {
      _logger.e('TTS init failed', error: error);
      return false;
    }
  }

  @override
  Future<bool> speak(String text) async {
    if (text.trim().isEmpty) return true;
    if (!await isKoreanAvailable()) return false;
    try {
      // IMPORTANT: awaitSpeakCompletion 을 켰으므로 이 await 가 재생 종료까지 기다린다.
      // 완료와 오류가 이 한 지점으로 모여야 호출자가 한 곳에서 처리한다.
      await _tts.speak(text);
      return true;
    } catch (error) {
      _logger.w('TTS speak failed: $error');
      return false;
    }
  }

  @override
  Future<void> stop() async => _tts.stop();

  @override
  Future<void> dispose() async => _tts.stop();
}
