import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/config.dart';
import 'core/design/tokens.dart';
import 'core/di.dart';
import 'core/l10n/strings.dart';
import 'ui/home/startup_screen.dart';

/// 앱 진입점.
///
/// 지금은 서버 왕복을 확인하는 자리표시 화면만 띄운다. 실제 화면은 목업이 확정된 뒤
/// `ui/` 하위에 채운다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // `.env` 가 없어도 앱이 떠야 한다. 없으면 설정이 비어 있다고 화면이 말한다.
  await dotenv.load(fileName: '.env', isOptional: true);
  await registerDependencies(AppConfig.fromEnv());
  runApp(const TodayMealApp());
}

class TodayMealApp extends StatelessWidget {
  const TodayMealApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Strings.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness: Brightness.light),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: const StartupScreen(),
    );
  }
}
