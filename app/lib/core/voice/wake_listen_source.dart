/// 호출어 청취의 한 구간.
///
/// 감지기에서 "듣는 수단"을 떼어낸 이유는 둘이다 — 기기 없이 감지 루프(매칭·재시작·
/// 백오프)를 시험할 수 있어야 하고, 인식 수단이 바뀌어도 루프를 건드리지 않아야 한다.
library;

import 'dart:async';

import 'package:logger/logger.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'speech_engine.dart';

/// 한 구간 동안 전사를 흘려주는 청취 수단.
abstract interface class WakeListenSource {
  /// 쓸 수 있는지 확인한다. 준비에 실패하면 `false`.
  Future<bool> prepare();

  /// 한 구간 동안 듣는다.
  ///
  /// 전사가 갱신될 때마다 [onTranscript] 를 부르고, 구간이 끝나면 반환한다. 인식
  /// 서비스는 침묵이 이어지면 스스로 구간을 끝내므로 **호출자가 반복해서 불러야**
  /// 상시 대기가 된다.
  Future<void> listenOnce(void Function(String transcript) onTranscript);

  /// 진행 중인 구간을 중단하고 마이크를 놓는다.
  Future<void> abort();
}

/// 기기 내장 인식 서비스로 구간을 듣는다.
///
/// CAUTION: 상시 청취이고 **오디오가 기기 밖으로 나간다.** `onDevice: true` 로
/// 요청하면 갤럭시 SM-E426S 는 한국어 온디바이스 모델이 없어 매 구간
/// `error_language_not_supported` 로 거부하고 아무것도 듣지 못한다. 그래서 온라인
/// 인식을 쓴다 — 완전 오프라인이라고 표현하지 않는다.
///
/// TODO: 온디바이스 한국어가 있는 기기에서는 `onDevice` 를 켜는 것이 낫다. 기기별
/// 지원 여부를 먼저 조회하는 경로가 필요하다.
///
/// CAUTION: 전용 호출어 엔진과 달리 배터리·발열 비용이 크다. 주방 고정 태블릿의
/// 상시 대기는 전용 엔진이 필요한 후속 범위다.
class DeviceWakeListenSource implements WakeListenSource {
  DeviceWakeListenSource({required SpeechEngine engine, Logger? logger})
      : _engine = engine,
        _logger = logger ?? Logger(printer: SimplePrinter());

  /// 한 구간의 최대 길이. 길게 두어 재시작 횟수를 줄인다.
  static const segment = Duration(seconds: 30);

  /// 침묵으로 구간을 끝내기까지의 시간. 짧으면 재시작이 잦아진다.
  static const silence = Duration(seconds: 8);

  final SpeechEngine _engine;
  final Logger _logger;

  @override
  Future<bool> prepare() => _engine.ensureReady();

  @override
  Future<void> listenOnce(void Function(String transcript) onTranscript) async {
    final ended = Completer<void>();
    late final StreamSubscription<String> statusSub;
    late final StreamSubscription<String> errorSub;

    void finish() {
      if (!ended.isCompleted) ended.complete();
    }

    statusSub = _engine.statuses.listen((status) {
      if (status == 'notListening' || status == 'done') finish();
    });
    // 침묵으로 끝나는 구간은 error_speech_timeout 으로 온다. 오류든 정상 종료든
    // 구간을 닫고 다음 구간을 여는 것이 상시 대기다.
    errorSub = _engine.errors.listen((_) => finish());

    try {
      await _engine.plugin.listen(
        listenOptions: SpeechListenOptions(
          localeId: 'ko_KR',
          partialResults: true,
          // 호출어는 중간 결과로 잡는다. 오류마다 구간을 끊고 새로 시작한다.
          cancelOnError: true,
          // 호출어 뒤에 명령이 이어질 수 있어 확정 모드가 아니라 받아쓰기 모드다.
          listenMode: ListenMode.dictation,
          pauseFor: silence,
          listenFor: segment,
        ),
        onResult: (result) => onTranscript(result.recognizedWords),
      );
      // 구간이 끝나는 경로가 상태 콜백뿐이면 콜백이 오지 않는 기기에서 영구 대기한다.
      await ended.future.timeout(segment + silence, onTimeout: () {
        _logger.d('Wake listen segment ended by timeout');
      });
    } finally {
      await statusSub.cancel();
      await errorSub.cancel();
    }
  }

  @override
  Future<void> abort() => _engine.release();
}
