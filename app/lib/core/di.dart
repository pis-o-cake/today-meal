import 'package:get_it/get_it.dart';

import 'config.dart';
import 'network/api_client.dart';

/// 의존성 등록소.
///
/// ViewModel 은 구현이 아니라 계약에 의존한다. 등록은 여기 한 곳에서만 한다 — 화면마다
/// 생성자를 타고 넘기면 목업이 붙을 때 배선이 흩어진다.
final GetIt di = GetIt.instance;

/// 앱 기동 시 한 번 부른다.
Future<void> registerDependencies(AppConfig config) async {
  di
    ..registerSingleton<AppConfig>(config)
    ..registerLazySingleton<ApiClient>(() => ApiClient(di<AppConfig>()));

  // TODO: 목업이 확정되면 Repository 와 ViewModel 을 여기 등록한다.
  //  음성 계층(VoiceSessionManager)은 S-01 에서 실제 플러그인을 배선한 뒤 등록한다.
}
