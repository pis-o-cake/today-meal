import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 실행 설정. 비밀값과 환경별 주소는 `.env` 에서만 온다.
///
/// 소스에 박지 않는다. `.env` 는 커밋하지 않으며 스테이징 내용은 pre-commit 훅이 검사한다.
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    this.wakeWordEnabled = true,
    this.kakaoNativeAppKey = '',
  });

  /// `.env` 를 읽어 설정을 만든다.
  ///
  /// 값이 없으면 빈 문자열로 둔다. 기본 서버 주소를 코드에 박으면 남의 서버에 붙는 사고가
  /// 나므로 주소만은 없으면 없는 대로 둔다.
  factory AppConfig.fromEnv() => AppConfig(
        apiBaseUrl: dotenv.maybeGet('API_BASE_URL') ?? '',
        wakeWordEnabled:
            (dotenv.maybeGet('WAKE_WORD_ENABLED') ?? 'true').toLowerCase() != 'false',
        kakaoNativeAppKey: dotenv.maybeGet('KAKAO_NATIVE_APP_KEY') ?? '',
      );

  /// 앱 서버 주소. 끝에 슬래시가 붙어야 한다.
  final String apiBaseUrl;

  /// 호출어 감지를 켤지.
  ///
  /// 끄면 마이크 버튼만 쓴다. 기기에서 감지기가 문제를 일으킬 때 원인을 가르는 스위치이자,
  /// 배터리를 아끼고 싶을 때의 설정이다.
  final bool wakeWordEnabled;

  /// 카카오 네이티브 앱 키.
  ///
  /// 없으면 카카오 로그인을 **켜지 않는다.** 버튼은 그대로 두되 눌렀을 때 아직
  /// 준비되지 않았다고 말한다 — 감추면 왜 없는지 알 수 없고, 열어 두면 눌러도
  /// 아무 일이 없다.
  ///
  /// WARNING: 네이티브 앱 키는 앱 안에 들어가므로 완전한 비밀이 아니다. 이 키만으로는
  /// 남의 계정에 들어갈 수 없다 — 서버가 카카오에 직접 토큰을 물어 확인한다.
  final String kakaoNativeAppKey;

  bool get hasServer => apiBaseUrl.isNotEmpty;

  bool get hasKakao => kakaoNativeAppKey.isNotEmpty;
}
