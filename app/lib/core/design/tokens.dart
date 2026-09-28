import 'package:flutter/material.dart';

/// 색·간격·그림자·글자의 정본.
///
/// 목업(`mockup/canvas/`)의 디자인 언어를 그대로 옮긴 것이다. 화면마다 값을 다시 정하지
/// 않는다 — 한 곳에서 바꾸면 전부 따라와야 한다.
///
/// 배색은 **밝은 글라스**다. 흰 반투명 판을 라디얼 그라데이션 위에 얹고, 상태색은
/// 재료 신선도([Bands])가 정한다. 화면 자체가 상태를 말하는 구조라서 화면 배경색이
/// 고정이 아니다.
abstract final class Tokens {
  // 글자. 세 단계로만 쓴다.
  static const ink = Color(0xFF15181D);
  static const inkMuted = Color(0xFF3E454E);
  static const inkFaint = Color(0xFF5F6670);

  /// 글라스 판. 배경 그라데이션이 비쳐야 하므로 불투명하게 쓰지 않는다.
  static const glass = Color(0xBDFFFFFF);

  /// 조금 더 불투명한 글라스. 본문이 올라가는 카드에 쓴다.
  static const glassSolid = Color(0xD6FFFFFF);

  /// 글라스 테두리. 판의 윗면을 세우는 역할이라 거의 흰색이다.
  static const glassEdge = Color(0xF2FFFFFF);

  /// 구분선.
  static const hairline = Color(0x12151D1D);

  /// 듣는 중 오버레이. 화면 전체를 덮는 어두운 층이다.
  static const overlay = Color(0xFF0A0C11);

  /// 오버레이 위의 강조. 인식된 재료 이름에 쓴다.
  static const overlayAccent = Color(0xFFC4B2FF);

  /// 오버레이 위의 그래프 선.
  static const overlayGraph = Color(0xFFA68BFA);

  // 여백.
  static const gutterCompact = 20.0;
  static const gutterWide = 32.0;
  static const gapCard = 16.0;
  static const gapTight = 8.0;

  // 둥글기. 알약은 999 대신 StadiumBorder 를 쓴다.
  static const radiusCard = 24.0;
  static const radiusTile = 20.0;
  static const radiusChip = 8.0;
  static const radiusNav = 32.0;

  /// 떠 있는 판의 그림자. 진하게 두면 밝은 배경에서 탁해진다.
  static const shadowRaised = <BoxShadow>[
    BoxShadow(color: Color(0x12141923), blurRadius: 18, offset: Offset(0, 6)),
  ];

  /// 카드 그림자.
  static const shadowCard = <BoxShadow>[
    BoxShadow(color: Color(0x14141923), blurRadius: 28, offset: Offset(0, 10)),
  ];

  /// 주 행동 버튼의 그림자. 화면에서 가장 앞에 있어야 한다.
  static const shadowAction = <BoxShadow>[
    BoxShadow(color: Color(0x21141923), blurRadius: 28, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x0F141923), blurRadius: 5, offset: Offset(0, 2)),
  ];

  /// 캐릭터 표정의 선·눈·입 색.
  static const faceInk = Color(0xFF333A52);

  /// 볼터치.
  static const blush = Color(0xFFFF7A8A);
}

/// 앱 테마.
///
/// 화면 배경은 [Bands] 가 정하는 그라데이션이라 `scaffoldBackgroundColor` 는 흰색으로
/// 두고 각 화면이 그 위에 그린다.
///
/// TODO: 목업은 Pretendard 를 쓴다. 폰트 파일을 받으면 `fontFamily` 를 지정한다. 지금은
/// 기기 기본 한글 폰트로 떨어진다.
ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF4FC178),
    brightness: Brightness.light,
  ).copyWith(
    surface: Colors.white,
    onSurface: Tokens.ink,
    onSurfaceVariant: Tokens.inkFaint,
    error: const Color(0xFFD8431F),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    // 자간을 좁혀야 목업의 촘촘한 인상이 난다.
    textTheme: const TextTheme(
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
      bodyLarge: TextStyle(fontSize: 15, height: 1.5, letterSpacing: -0.3),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, letterSpacing: -0.28),
      labelLarge: TextStyle(
        fontSize: 14, height: 1.4, fontWeight: FontWeight.w700, letterSpacing: -0.28),
      labelMedium: TextStyle(
        fontSize: 13, height: 1.4, fontWeight: FontWeight.w600, letterSpacing: -0.26),
      labelSmall: TextStyle(
        fontSize: 12, height: 1.35, fontWeight: FontWeight.w700, letterSpacing: -0.24),
    ),
  );
}
