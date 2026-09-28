import 'package:flutter/material.dart';

/// 색·간격·글자 크기의 정본.
///
/// 화면마다 값을 다시 정하지 않는다. **주방에서 서 있는 거리에서 읽는** 경우가 있어
/// 본문을 일반 앱보다 키우고, 태블릿 거치 상태에서도 같은 값을 쓴다.
abstract final class Tokens {
  static const charcoal = Color(0xFF12100E);
  static const charcoalRaised = Color(0xFF1E1B18);
  static const cream = Color(0xFFF5F0E6);
  static const creamDim = Color(0xFFA8A29A);
  static const lime = Color(0xFFC8E64C);
  static const warm = Color(0xFFE8A33D);
  static const alert = Color(0xFFE0603C);

  /// 핸드폰 좌우 여백.
  static const gutterCompact = 20.0;

  /// 태블릿 좌우 여백.
  static const gutterWide = 32.0;

  static const gapCard = 16.0;
  static const gapTight = 8.0;
  static const cardRadius = 20.0;
}

/// 앱 테마.
///
/// 대기 화면이 낮은 밝기여야 해 어두운 배색을 기본으로 둔다.
ThemeData buildTheme({Brightness brightness = Brightness.dark}) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Tokens.lime,
    brightness: brightness,
  ).copyWith(
    primary: isDark ? Tokens.lime : const Color(0xFF6B7F14),
    onPrimary: Tokens.charcoal,
    secondary: Tokens.warm,
    surface: isDark ? Tokens.charcoalRaised : Tokens.cream,
    onSurface: isDark ? Tokens.cream : Tokens.charcoal,
    onSurfaceVariant: isDark ? Tokens.creamDim : const Color(0xFF5A554E),
    error: Tokens.alert,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? Tokens.charcoal : Tokens.cream,
    // 멀리서 읽히도록 키운 타이포.
    textTheme: const TextTheme(
      displaySmall: TextStyle(fontSize: 36, height: 1.2, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(fontSize: 28, height: 1.25, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(fontSize: 22, height: 1.3, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 18, height: 1.4),
      bodyMedium: TextStyle(fontSize: 16, height: 1.45),
      labelLarge: TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w500),
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.cardRadius),
      ),
    ),
  );
}
