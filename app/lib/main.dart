import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/config.dart';
import 'core/design/tokens.dart';
import 'core/di.dart';
import 'core/l10n/strings.dart';
import 'ui/conversation/conversation_view_model.dart';
import 'ui/fridge/fridge_view_model.dart';
import 'ui/history/history_view_model.dart';
import 'ui/home/home_view_model.dart';
import 'ui/shell.dart';

/// 앱 진입점.
///
/// UI 는 계속 바뀔 것을 전제로 구조만 잡았다. 데이터 흐름과 상태 전이가 확정된 자리에
/// 화면을 갈아 끼운다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // `.env` 가 없어도 앱이 떠야 한다. 없으면 설정이 비어 있다고 화면이 말한다.
  await dotenv.load(fileName: '.env', isOptional: true);
  await initializeDateFormatting('ko');
  await registerDependencies(AppConfig.fromEnv());
  runApp(const TodayMealApp());
}

class TodayMealApp extends StatelessWidget {
  const TodayMealApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: di<HomeViewModel>()),
        ChangeNotifierProvider.value(value: di<FridgeViewModel>()),
        ChangeNotifierProvider.value(value: di<HistoryViewModel>()),
        ChangeNotifierProvider.value(value: di<ConversationViewModel>()),
      ],
      child: MaterialApp(
        title: Strings.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        darkTheme: buildTheme(),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    );
  }
}
