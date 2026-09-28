/// 음성 세션의 상태.
///
/// 화면은 이 값 하나만 보고 그린다. 마이크를 누가 점유했는지는 `VoiceSessionManager` 만
/// 알고 있으며, 상태를 색만으로 구분하지 않고 문구와 함께 표시한다.
///
/// ```
/// Waiting → Listening → Processing → Speaking → Waiting
///                          ↓
///                      Clarifying → Listening
/// ```
sealed class VoiceState {
  const VoiceState();
}

/// 웨이크워드 대기. 감지기가 마이크를 갖고 있다.
final class Waiting extends VoiceState {
  const Waiting();
}

/// 호출을 감지해 명령을 전사하는 중. 전사기가 마이크를 갖고 있다.
final class Listening extends VoiceState {
  const Listening({this.partialText, this.level = 0});

  final String? partialText;

  /// 마이크 입력 크기(0~1).
  ///
  /// 듣는 중 연출이 목소리에 반응하는 근거다. 기기마다 범위가 달라 **정확한 크기가
  /// 아니라 세기**로만 쓴다.
  final double level;
}

/// 서버가 처리하는 중. 마이크를 아무도 갖지 않는다.
final class Processing extends VoiceState {
  const Processing(this.utterance);

  final String utterance;
}

/// 서버가 한 가지를 되묻는 중.
///
/// 호출어를 반복하지 않아도 답할 수 있게 짧은 후속 응답 창을 연다. 시간이 초과되면
/// 확인되지 않은 임시 변경을 적용하지 않고 [Waiting] 으로 돌아간다.
final class Clarifying extends VoiceState {
  const Clarifying(this.question);

  final String question;
}

/// 응답을 읽는 중.
///
/// 이 동안 전사를 멈춘다. 멈추지 않으면 자기 응답을 다시 명령으로 처리한다.
final class Speaking extends VoiceState {
  const Speaking(this.text);

  final String text;
}

/// 사용자가 음소거했다. 대기 중으로 표시하지 않는다.
final class Muted extends VoiceState {
  const Muted();
}

/// 앱이 배경으로 가서 감지를 멈췄다.
///
/// **웨이크워드는 전경 한정이다.** 핸드폰에서 상시 대기는 성립하지 않으므로 배경에서는
/// 감지하지 않으며, 대기 중인 것처럼 보이게 두지 않는다. 백그라운드 상시 대기는
/// 주방 고정 태블릿을 위한 후속 범위다.
final class Suspended extends VoiceState {
  const Suspended();
}

/// 마이크를 쓸 수 없다.
///
/// 권한 해제·통화·다른 앱의 오디오 점유로 감지가 멈춘 상태다. 실제 상태를 그대로
/// 보여주며 대기 중인 것처럼 표시하지 않는다.
final class Unavailable extends VoiceState {
  const Unavailable(this.reason);

  final UnavailableReason reason;
}

/// 사용할 수 없는 이유. 화면 문구를 가른다.
enum UnavailableReason {
  missingPermission,
  wakeWordInitFailed,
  recognizerUnavailable,
  ttsUnavailable,
  audioInterrupted,
}
