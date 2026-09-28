/// 사용자에게 보이는 문구.
///
/// **위젯에 한국어를 직접 적지 않는다.** 로그와 내부 예외는 영어로 고정하고, 이 파일이
/// 다루는 것은 사용자에게 보이는 문구뿐이다.
///
/// 지금은 한국어만 있다. 언어가 늘면 이 클래스를 인터페이스로 바꾸고 언어별 구현을 둔다.
class Strings {
  const Strings._();

  static const appName = '오늘 뭐 먹지?';

  // 음성 상태. 색만으로 구분하지 않고 문구를 함께 쓴다.
  static const voiceWaiting = '호출 대기 중';
  static const voiceListening = '듣고 있어요';
  static const voiceProcessing = '확인하고 있어요';
  static const voiceSpeaking = '답하고 있어요';
  static const voiceClarifying = '한 가지만 확인할게요';
  static const voiceMuted = '음소거';
  static const voiceSuspended = '앱을 열어두면 불러서 쓸 수 있어요';
  static const voiceUnavailable = '마이크를 쓸 수 없어요';
  static const voiceRetry = '다시 말해주세요';
  static const wakeWordHint = '"헤이 냉장고, 오늘 뭐 먹지?"';

  // 서버 연결
  static const serverChecking = '서버에 연결하는 중';
  static const serverConnected = '서버에 연결됐어요';
  static const serverMissing = '서버 주소가 설정되지 않았어요';
  static const serverFailed = '서버에 연결할 수 없어요';
  static const retry = '다시 시도';

  // 아직 화면이 없는 자리
  static const uiPending = '화면은 목업 확정 후에 만듭니다';
}
