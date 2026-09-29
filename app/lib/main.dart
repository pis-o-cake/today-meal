import 'package:flutter/material.dart';
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
import 'ui/fridge/fridge_view_model.dart';
import 'ui/history/history_view_model.dart';
import 'ui/home/home_view_model.dart';

/// 앱 진입점.
///
/// 화면 테마는 첫 프레임 전에 읽는다 — 나중에 읽으면 기본 테마로 한 번 그렸다가 바뀌어
/// 화면이 번쩍인다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // `.env` 가 없어도 앱이 떠야 한다. 없으면 설정이 비어 있다고 화면이 말한다.
  await dotenv.load(fileName: '.env', isOptional: true);
  await initializeDateFormatting('ko');
  await registerDependencies(AppConfig.fromEnv());

  final settings = await AppSettings.load();
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
          );
        },
      ),
    );
  }
}
