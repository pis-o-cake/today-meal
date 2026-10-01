import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/config.dart';
import 'core/design/skin.dart';
import 'core/design/tokens.dart';
import 'core/di.dart';
import 'core/l10n/strings.dart';
import 'core/settings/app_settings.dart';
import 'domain/repository/repositories.dart';
import 'ui/app_root.dart';
import 'ui/conversation/conversation_view_model.dart';
import 'ui/cook/cook_view_model.dart';
import 'ui/fridge/fridge_view_model.dart';
import 'ui/history/history_view_model.dart';
import 'ui/home/home_view_model.dart';

/// 앱 진입점.
///
/// 화면 테마는 첫 프레임 전에 읽는다 — 나중에 읽으면 기본 테마로 한 번 그렸다가 바뀌어
/// 화면이 번쩍인다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 시스템 막대 뒤까지 앱이 그린다. 기기의 내비게이션 바가 우리 탭 바와 다른 색으로
  // 남으면 화면 아래가 두 층으로 끊긴다 — 테마를 바꿔도 그 띠만 그대로다.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // `.env` 가 없어도 앱이 떠야 한다. 없으면 설정이 비어 있다고 화면이 말한다.
  await dotenv.load(fileName: '.env', isOptional: true);
  await initializeDateFormatting('ko');
  // 설정을 먼저 읽는다. 음성·추천이 이 값을 보고 동작하므로 등록보다 앞서야 한다.
  final settings = await AppSettings.load();
  await registerDependencies(AppConfig.fromEnv(), settings: settings);

  runApp(TodayMealApp(settings: settings));
}

class TodayMealApp extends StatelessWidget {
  const TodayMealApp({required this.settings, super.key});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: di<HomeViewModel>()),
        ChangeNotifierProvider.value(value: di<CookViewModel>()),
        ChangeNotifierProvider.value(value: di<FridgeViewModel>()),
        ChangeNotifierProvider.value(value: di<HistoryViewModel>()),
        ChangeNotifierProvider.value(value: di<ConversationViewModel>()),
      ],
      // 테마가 바뀌면 `MaterialApp` 까지 다시 만든다. 글자색과 배경이 한 프레임에
      // 함께 바뀌어야 중간 상태가 보이지 않는다.
      child: Consumer<AppSettings>(
        builder: (context, settings, _) {
          final skin = Skins.of(settings.skin);
          return SkinScope(
            skin: skin,
            // 시스템 막대는 투명하고 아이콘 색만 테마를 따른다. 색을 지정하면 우리가
            // 그린 배경 위에 그 색이 덧칠돼 다시 띠가 생긴다.
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: _systemBars(skin),
              child: MaterialApp(
              title: Strings.appName,
              debugShowCheckedModeBanner: false,
              theme: buildTheme(skin),
              home: AppRoot(
                auth: di<AuthRepository>(),
                // 스플래시와 함께 재고만 미리 읽는다. 추천은 모델 호출이라 느려서
                // 여기서 기다리면 스플래시가 몇 초씩 붙잡힌다 — 셸이 들어가며 읽는다.
                  prepare: () =>
                      context.read<HomeViewModel>().load(withMenus: false),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 시스템 막대의 아이콘 색.
///
/// 배경을 투명하게 두고 아이콘 밝기만 정한다. 어두운 테마에서는 밝은 아이콘이라야
/// 보이고, 밝은 테마에서는 그 반대다. **색을 칠하지 않는 것이 핵심이다** — 칠하면 앱이
/// 그린 배경과 다른 띠가 화면 위아래에 남는다.
SystemUiOverlayStyle _systemBars(Skin skin) {
  final icons = skin.isDark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: icons,
    // iOS 는 반대로 읽는다. 밝은 배경에서 `dark` 를 쓰면 아이콘이 사라진다.
    statusBarBrightness: skin.isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  );
}
