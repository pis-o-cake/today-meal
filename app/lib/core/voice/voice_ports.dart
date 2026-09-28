/// 음성 계층의 계약.
///
/// 구현은 `speech_to_text` · `flutter_tts` 를 감싼다. 인터페이스를 두는 이유는 둘이다 —
/// 실기기 검증에서 막혔을 때 교체 지점이 필요하고, **기기 없이 상태기계를 시험할 수
/// 있어야** 한다. 호출어 수단을 두 번 갈아치우는 동안 이 계약은 그대로였다.
library;

/// 웨이크워드 감지기.
///
/// **이 감지기와 [SpeechTranscriber] 는 마이크를 동시에 점유할 수 없다.** 소유권을
/// 넘기는 책임은 `VoiceSessionManager` 하나가 갖는다. 이 인터페이스의 구현이 직접
/// 전사기를 부르지 않는다.
abstract interface class WakeWordDetector {
  /// 감지 이벤트. 구독하는 동안만 마이크를 점유한다.
  Stream<void> get detections;

  /// 감지를 시작한다.
  ///
  /// 인식 수단을 준비할 수 없으면 예외를 던진다. 조용히 성공하면 감지되는 것으로
  /// 착각한다.
  Future<void> start();

  /// 감지를 멈추고 마이크를 놓는다.
  ///
  /// 전사를 시작하기 전에 반드시 호출해야 한다. 마이크를 놓지 않으면 전사기가 시작하지
  /// 못한다.
  Future<void> stop();

  /// 자원을 해제한다.
  Future<void> dispose();
}

/// 호출 이후의 명령을 텍스트로 바꾼다.
///
/// 대기 중 청취는 [WakeWordDetector] 의 몫이고 이 포트는 **호출 이후 한 번**만 쓴다.
/// 둘이 같은 인식 플러그인을 쓰므로 `SpeechEngine` 을 공유한다.
///
/// 내장 서비스가 항상 기기 내에서 처리되는 것은 아니다. 완전 오프라인 STT 라고
/// 표현하지 않는다.
abstract interface class SpeechTranscriber {
  /// 기기에 인식 서비스가 있는지. 없으면 텍스트 입력 경로만 제공한다.
  Future<bool> isAvailable();

  /// 한 번의 명령을 전사한다.
  ///
  /// 발화 종료는 인식 서비스의 콜백을 기준으로 판정한다. 무음 종료 시간 설정은 기기마다
  /// 지원이 달라 동일한 동작을 가정하지 않으며, 호출자가 별도 타임아웃을 함께 건다.
  ///
  /// 인식 실패·오디오 중단 시 [TranscriptionException] 을 던진다.
  /// [onLevel] 은 마이크 입력 크기다. 0 에 가까우면 조용하고 1 에 가까우면 크다.
  /// 듣는 중 연출이 목소리에 반응하려면 이 값이 필요하다.
  Future<String> transcribeOnce({
    String localeId = 'ko_KR',
    void Function(String partial)? onPartial,
    void Function(double level)? onLevel,
  });

  /// 진행 중인 전사를 취소하고 마이크를 놓는다.
  Future<void> cancel();
}

/// 전사 실패. 메시지는 로그용이므로 영어로 고정한다.
class TranscriptionException implements Exception {
  const TranscriptionException(this.message);

  final String message;

  @override
  String toString() => 'TranscriptionException: $message';
}

/// 응답을 읽는다.
///
/// 기기에 한국어 음성이 없으면 낭독이 되지 않으므로 [isKoreanAvailable] 로 먼저 확인한다.
abstract interface class SpeechSpeaker {
  /// 한국어 음성을 쓸 수 있는지.
  Future<bool> isKoreanAvailable();

  /// 한 문장을 읽는다. 재생이 끝나면 반환한다.
  ///
  /// 호출자는 완료와 실패 **양쪽** 경로에서 감지기를 재기동해야 한다. 한쪽만 걸면 실패
  /// 경로에서 대기로 돌아오지 못한다. 그래서 실패 시 예외를 던지지 않고 `false` 를
  /// 돌려주어 호출자가 한 곳에서 처리하게 한다.
  Future<bool> speak(String text);

  /// 재생을 멈춘다.
  Future<void> stop();

  /// 자원을 해제한다.
  Future<void> dispose();
}

/// 한 번의 대화 처리 결과.
///
/// 서버 응답을 음성 계층이 이해할 수 있는 형태로 줄인 것이다. 재고 판정은 서버가 하고
/// 이 타입은 "무엇을 읽고 다음에 무엇을 할지"만 담는다.
sealed class VoiceTurnResult {
  const VoiceTurnResult();
}

/// 처리를 마쳤다. [spoken] 을 읽고 대기로 돌아간다.
final class TurnAnswered extends VoiceTurnResult {
  const TurnAnswered(this.spoken);

  final String spoken;
}

/// 한 가지를 되물어야 한다.
final class TurnNeedsClarification extends VoiceTurnResult {
  const TurnNeedsClarification(this.question);

  final String question;
}

/// 실패했다. 성공한 것처럼 말하지 않는다.
final class TurnFailed extends VoiceTurnResult {
  const TurnFailed({required this.spoken, required this.logDetail});

  /// 사용자에게 읽어줄 문구.
  final String spoken;

  /// 로그에 남길 영어 설명.
  final String logDetail;
}
