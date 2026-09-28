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
import 'voice/device_speech.dart';
import 'voice/sherpa_wake_word_detector.dart';
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
    // 호출어 감지는 온디바이스(sherpa-onnx)이고 전사·낭독은 기기 내장 서비스다.
    // 셋을 싱글턴으로 두는 이유는 마이크를 다루는 객체가 여럿 생기면 소유권 관리가
    // 무의미해지기 때문이다.
    ..registerLazySingleton<SherpaWakeWordDetector>(SherpaWakeWordDetector.new)
    ..registerLazySingleton<VoiceSessionManager>(
      () => VoiceSessionManager(
        detector: di<SherpaWakeWordDetector>(),
        transcriber: DeviceSpeechTranscriber(),
        speaker: DeviceSpeechSpeaker(),
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
