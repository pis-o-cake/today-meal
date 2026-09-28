import 'package:get_it/get_it.dart';

import '../data/repository/repositories_impl.dart';
import '../domain/repository/repositories.dart';
import '../ui/conversation/conversation_view_model.dart';
import '../ui/fridge/fridge_view_model.dart';
import '../ui/history/history_view_model.dart';
import '../ui/home/home_view_model.dart';
import 'config.dart';
import 'l10n/strings.dart';
import 'network/api_client.dart';
import 'voice/stub_voice.dart';
import 'voice/voice_session_manager.dart';

/// 의존성 등록소.
///
/// ViewModel 은 구현이 아니라 계약에 의존한다. 등록은 여기 한 곳에서만 한다 — 화면마다
/// 생성자를 타고 넘기면 배선이 흩어진다.
final GetIt di = GetIt.instance;

/// 앱 기동 시 한 번 부른다.
Future<void> registerDependencies(AppConfig config) async {
  di
    ..registerSingleton<AppConfig>(config)
    ..registerLazySingleton<ApiClient>(() => ApiClient(di<AppConfig>()))
    ..registerLazySingleton<InventoryRepository>(
      () => RemoteInventoryRepository(di<ApiClient>()),
    )
    ..registerLazySingleton<CommandRepository>(
      () => RemoteCommandRepository(di<ApiClient>()),
    )
    ..registerLazySingleton<MenuRepository>(
      () => RemoteMenuRepository(di<ApiClient>()),
    )
    // 음성 계층은 아직 자리표시 구현이다. 실제 플러그인 배선은 S-01 에서 한다.
    // 자리표시가 조용히 성공하면 감지되는 것으로 착각하므로 예외를 던진다.
    ..registerLazySingleton<VoiceSessionManager>(
      () => VoiceSessionManager(
        detector: StubWakeWordDetector(),
        transcriber: StubSpeechTranscriber(),
        speaker: StubSpeechSpeaker(),
        retryMessage: Strings.voiceRetry,
      ),
    )
    ..registerLazySingleton<HomeViewModel>(
      () => HomeViewModel(
        inventory: di<InventoryRepository>(),
        menu: di<MenuRepository>(),
      ),
    )
    ..registerLazySingleton<FridgeViewModel>(
      () => FridgeViewModel(inventory: di<InventoryRepository>()),
    )
    ..registerLazySingleton<HistoryViewModel>(
      () => HistoryViewModel(command: di<CommandRepository>()),
    )
    ..registerLazySingleton<ConversationViewModel>(
      () => ConversationViewModel(
        voice: di<VoiceSessionManager>(),
        command: di<CommandRepository>(),
        retryMessage: Strings.voiceRetry,
      ),
    );
}
