import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 실행 설정. 비밀값과 환경별 주소는 `.env` 에서만 온다.
///
/// 소스에 박지 않는다. `.env` 는 커밋하지 않으며 스테이징 내용은 pre-commit 훅이 검사한다.
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.porcupineAccessKey,
    required this.wakeWordAsset,
  });

  /// `.env` 를 읽어 설정을 만든다.
  ///
  /// 값이 없으면 빈 문자열로 둔다. 기본 서버 주소를 코드에 박으면 남의 서버에 붙는 사고가
  /// 나므로 주소만은 없으면 없는 대로 둔다.
  factory AppConfig.fromEnv() => AppConfig(
        apiBaseUrl: dotenv.maybeGet('API_BASE_URL') ?? '',
        porcupineAccessKey: dotenv.maybeGet('PORCUPINE_ACCESS_KEY') ?? '',
        wakeWordAsset: dotenv.maybeGet('WAKE_WORD_ASSET') ?? '',
      );

  /// 앱 서버 주소. 끝에 슬래시가 붙어야 한다.
  final String apiBaseUrl;

  /// Porcupine AccessKey.
  ///
  /// 없으면 웨이크워드를 기동하지 않고 그 사실을 화면에 표시한다. 조용히 넘기면 감지되는
  /// 것으로 착각한다.
  final String porcupineAccessKey;

  /// 한국어 커스텀 호출어 모델 파일명.
  final String wakeWordAsset;

  bool get hasServer => apiBaseUrl.isNotEmpty;

  bool get hasWakeWord =>
      porcupineAccessKey.isNotEmpty && wakeWordAsset.isNotEmpty;
}
