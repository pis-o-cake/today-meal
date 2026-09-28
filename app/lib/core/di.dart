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
import 'voice/device_wake_word_detector.dart';
import 'voice/speech_engine.dart';
import 'voice/voice_ports.dart';
import 'voice/wake_listen_source.dart';
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
    // IMPORTANT: 호출어 감지와 전사가 같은 인식 플러그인을 쓴다. 엔진을 하나로 묶지
    // 않으면 initialize 콜백이 서로를 덮어써 인식 실패를 놓친다.
    ..registerLazySingleton<SpeechEngine>(SpeechEngine.new)
    // 호출어 감지를 끄면 마이크 버튼만 쓴다. 감지기가 기기에서 문제를 일으킬 때
    // 원인을 가르는 스위치다.
    ..registerLazySingleton<WakeWordDetector>(
      () => config.wakeWordEnabled
          ? DeviceSpeechWakeWordDetector(
              source: DeviceWakeListenSource(engine: di<SpeechEngine>()),
            )
          : DisabledWakeWordDetector(),
    )
    ..registerLazySingleton<VoiceSessionManager>(
      () => VoiceSessionManager(
        detector: di<WakeWordDetector>(),
        transcriber: DeviceSpeechTranscriber(engine: di<SpeechEngine>()),
        speaker: DeviceSpeechSpeaker(),
        retryMessage: Strings.voiceRetry,
        ackMessage: Strings.voiceAck,
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
