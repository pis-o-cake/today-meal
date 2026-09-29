/// 간격·둥글기·글자의 정본.
///
/// 목업(`mockup/canvas/`)의 디자인 언어를 그대로 옮긴 것이다. 화면마다 값을 다시 정하지
/// 않는다 — 한 곳에서 바꾸면 전부 따라와야 한다.
///
/// **색은 여기 없다.** 화면 테마 4종이 같은 자리를 다른 색으로 그리므로 색은 [Skin] 이
/// 갖는다. 이 파일에는 테마와 무관한 값만 둔다.
library;

import 'package:flutter/material.dart';

import '../../domain/model/inventory.dart';
import 'skin.dart';

abstract final class Tokens {
  // 여백.
  static const gutterCompact = 20.0;
  static const gutterWide = 32.0;
  static const gapCard = 16.0;
  static const gapTight = 8.0;

  // 둥글기. 알약은 999 대신 StadiumBorder 를 쓴다.
  static const radiusCard = 24.0;
  static const radiusTile = 20.0;
  static const radiusPanel = 22.0;
  static const radiusField = 12.0;
  static const radiusChip = 8.0;
  static const radiusNav = 32.0;

  /// 터치 영역의 최소 한 변. 접근성 기준이며 줄이지 않는다.
  static const tap = 44.0;

  /// 캐릭터 표정의 선·눈·입 색. 테마와 무관하게 같은 먹색을 쓴다.
  static const faceInk = Color(0xFF333A52);

  /// 볼터치.
  static const blush = Color(0xFFFF7A8A);
}

/// 앱 테마.
///
/// 화면 배경은 [Skin.background] 가 정하는 그라데이션이라 `scaffoldBackgroundColor` 는
/// 투명에 가깝게 두고 각 화면이 그 위에 그린다.
///
/// 글꼴은 **Pretendard 가변 폰트**다. 목업과 같은 파일을 번들한다 — 기기 기본 한글
/// 폰트는 자간과 굵기가 달라 목업의 인상이 나오지 않는다.
ThemeData buildTheme(Skin skin) {
  final scheme = ColorScheme.fromSeed(
    seedColor: skin.primary,
    brightness: skin.isDark ? Brightness.dark : Brightness.light,
  ).copyWith(
    surface: skin.isDark ? const Color(0xFF202124) : Colors.white,
    onSurface: skin.ink,
    onSurfaceVariant: skin.inkFaint,
    error: skin.band(Freshness.urgent).accent,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: skin.isDark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    fontFamily: 'Pretendard',
    scaffoldBackgroundColor: scheme.surface,
    // 자간을 좁혀야 목업의 촘촘한 인상이 난다.
    textTheme: _textTheme.apply(bodyColor: skin.ink, displayColor: skin.ink),
  );
}

/// 목업의 글자 크기·굵기·자간.
///
/// CSS 의 `letter-spacing: -0.05em` 은 크기에 비례하므로 크기마다 값을 따로 적는다.
const _textTheme = TextTheme(
  displayLarge: TextStyle(
      fontSize: 46, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -2.3),
  displayMedium: TextStyle(
      fontSize: 42, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -2.1),
  displaySmall: TextStyle(
      fontSize: 32, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -1.6),
  headlineMedium: TextStyle(
      fontSize: 28, height: 1.2, fontWeight: FontWeight.w800, letterSpacing: -1.26),
  headlineSmall: TextStyle(
      fontSize: 23, height: 1.4, fontWeight: FontWeight.w700, letterSpacing: -0.8),
  titleLarge: TextStyle(
      fontSize: 20, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: -0.4),
  titleMedium: TextStyle(
      fontSize: 17, height: 1.35, fontWeight: FontWeight.w700, letterSpacing: -0.34),
  titleSmall: TextStyle(
      fontSize: 16, height: 1.4, fontWeight: FontWeight.w700, letterSpacing: -0.48),
  bodyLarge: TextStyle(fontSize: 15, height: 1.5, letterSpacing: -0.3),
  bodyMedium: TextStyle(fontSize: 14, height: 1.5, letterSpacing: -0.28),
  labelLarge: TextStyle(
      fontSize: 14, height: 1.4, fontWeight: FontWeight.w700, letterSpacing: -0.28),
  labelMedium: TextStyle(
      fontSize: 13, height: 1.4, fontWeight: FontWeight.w600, letterSpacing: -0.26),
  labelSmall: TextStyle(
      fontSize: 12, height: 1.35, fontWeight: FontWeight.w700, letterSpacing: -0.24),
);
