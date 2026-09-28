import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 실행 설정. 비밀값과 환경별 주소는 `.env` 에서만 온다.
///
/// 소스에 박지 않는다. `.env` 는 커밋하지 않으며 스테이징 내용은 pre-commit 훅이 검사한다.
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    this.wakeWordEnabled = true,
  });

  /// `.env` 를 읽어 설정을 만든다.
  ///
  /// 값이 없으면 빈 문자열로 둔다. 기본 서버 주소를 코드에 박으면 남의 서버에 붙는 사고가
  /// 나므로 주소만은 없으면 없는 대로 둔다.
  factory AppConfig.fromEnv() => AppConfig(
        apiBaseUrl: dotenv.maybeGet('API_BASE_URL') ?? '',
        wakeWordEnabled:
            (dotenv.maybeGet('WAKE_WORD_ENABLED') ?? 'true').toLowerCase() != 'false',
      );

  /// 앱 서버 주소. 끝에 슬래시가 붙어야 한다.
  final String apiBaseUrl;

  /// 호출어 감지를 켤지.
  ///
  /// 끄면 마이크 버튼만 쓴다. 기기에서 감지기가 문제를 일으킬 때 원인을 가르는 스위치이자,
  /// 배터리를 아끼고 싶을 때의 설정이다.
  final bool wakeWordEnabled;

  bool get hasServer => apiBaseUrl.isNotEmpty;
}
