import 'package:get_it/get_it.dart';

import '../data/remote/social_sign_in.dart';
import '../data/repository/repositories_impl.dart';
import '../domain/repository/repositories.dart';
import '../ui/conversation/conversation_view_model.dart';
import '../ui/cook/cook_view_model.dart';
import '../ui/fridge/fridge_view_model.dart';
import '../ui/history/history_view_model.dart';
import '../ui/home/home_view_model.dart';
import 'config.dart';
import 'settings/app_settings.dart';
import 'l10n/strings.dart';
import 'network/api_client.dart';
import 'voice/device_speech.dart';
import 'voice/device_wake_word_detector.dart';
import 'voice/listening_cue.dart';
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
///
/// [settings] 는 기기에 저장된 설정이다. 낭독 여부·기본 인분처럼 **동작을 바꾸는 설정**이
/// 있어 음성·추천이 이 값을 읽어야 한다 — 저장만 하고 아무것도 바꾸지 않으면 사용자에게
/// 거짓말이 된다.
Future<void> registerDependencies(
  AppConfig config, {
  required AppSettings settings,
}) async {
  di
    ..registerSingleton<AppConfig>(config)
    ..registerSingleton<AppSettings>(settings)
    ..registerLazySingleton<ApiClient>(() => ApiClient(di<AppConfig>()))
    ..registerLazySingleton<InventoryRepository>(
      () => RemoteInventoryRepository(di<ApiClient>()),
    )
    ..registerLazySingleton<CommandRepository>(
      () => RemoteCommandRepository(di<ApiClient>()),
    )
    // 카카오 키가 없으면 제공자를 끼우지 않는다. 버튼은 그대로 두되 눌렀을 때
    // "준비 중" 으로 답한다 — 감추면 왜 없는지 알 수 없다.
    ..registerLazySingleton<SocialSignIn>(
      () => config.hasKakao
          ? KakaoSignIn(nativeAppKey: config.kakaoNativeAppKey)
          : const NoSocialSignIn(),
    )
    ..registerLazySingleton<AuthRepository>(
      () => RemoteAuthRepository(di<ApiClient>(), social: di<SocialSignIn>()),
    )
    ..registerLazySingleton<MenuRepository>(
      () => RemoteMenuRepository(di<ApiClient>()),
    )
    // 서버 주소가 없는 빌드에서는 정리하지 못한다. 실패를 "준비 중" 이 아니라
    // 연결 없음으로 답한다 — 사용자가 링크를 고치려 애쓰지 않게 한다.
    ..registerLazySingleton<VideoRepository>(
      () => RemoteVideoRepository(di<ApiClient>(), connected: config.hasServer),
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
        retryMessage: Strings.voiceNotApplied,
        // IMPORTANT: 호출 응답을 말("네?")로 하지 않는다. 낭독이 끝나야 듣기 시작하므로
        // 호출 직후 바로 말한 앞부분이 잘렸다. 짧은 신호음으로 대신한다.
        listeningCue: ListeningCue().play,
        checkingMessage: Strings.voiceChecking,
        restartMessage: Strings.voiceSayAgain,
        // 음성 응답 설정이 실제로 낭독을 끈다. 마이크 음소거와 다른 설정이다.
        spokenReply: () => di<AppSettings>().spokenReply,
      ),
    )
    ..registerLazySingleton<HomeViewModel>(
      () => HomeViewModel(
        inventory: di<InventoryRepository>(),
        menu: di<MenuRepository>(),
        defaultServings: () => di<AppSettings>().defaultServings,
      ),
    )
    ..registerLazySingleton<CookViewModel>(
      () => CookViewModel(
        menu: di<MenuRepository>(),
        video: di<VideoRepository>(),
        defaultServings: () => di<AppSettings>().defaultServings,
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
        retryMessage: Strings.voiceNotApplied,
      ),
    );
}
