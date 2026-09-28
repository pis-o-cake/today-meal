/// 신선도 등급마다의 배색.
///
/// 목업의 핵심 장치다 — 화면 배경·강조색·캐릭터 색이 **가장 급한 재료의 등급**을 따라
/// 함께 바뀐다. 사용자는 앱을 열자마자 색으로 상황을 읽고, 글자로 확인한다.
///
/// 색만으로 구분하지 않는다. 등급마다 문구([Strings])가 항상 함께 나간다.
library;

import 'package:flutter/material.dart';

import '../../domain/model/inventory.dart';

/// 한 등급의 배색 묶음.
class BandPalette {
  const BandPalette({
    required this.accent,
    required this.accentSoft,
    required this.bgMid,
    required this.bgEdge,
    required this.mascotBody,
    required this.mood,
  });

  /// 등급 이름과 화살표에 쓰는 강조색. 배경 위에서 대비를 확보한 값이다.
  final Color accent;

  /// 강조색의 옅은 판. 대기 점의 후광에 쓴다.
  final Color accentSoft;

  /// 배경 그라데이션의 중간 색.
  final Color bgMid;

  /// 배경 그라데이션의 바깥 색.
  final Color bgEdge;

  /// 아치 위 얼굴 토큰의 몸 색.
  final Color mascotBody;

  /// 캐릭터 표정.
  final MascotMood mood;

  /// 화면 배경. 위쪽에서 흰빛이 퍼지는 라디얼 그라데이션이다.
  ///
  /// `radial-gradient(125% 80% at 50% 20%, #FFF, bgMid 42%, bgEdge 100%)` 을 옮긴 것이다.
  Gradient get background => RadialGradient(
        center: const Alignment(0, -0.6),
        radius: 1.25,
        colors: [Colors.white, bgMid, bgEdge],
        stops: const [0, 0.42, 1],
      );

  /// 목록 화면의 배경. 빛이 화면 꼭대기에서 온다.
  Gradient get listBackground => RadialGradient(
        center: const Alignment(0, -1),
        radius: 1.25,
        colors: [Colors.white, bgMid, bgEdge],
        stops: const [0, 0.45, 1],
      );
}

/// 캐릭터 표정. 신선도 5종에 음성 상태 3종을 더한 것이다.
enum MascotMood { expired, urgent, soon, fresh, unknown, listening, asking, done }

/// 등급별 팔레트 표.
abstract final class Bands {
  static const expired = BandPalette(
    accent: Color(0xFF6E7784),
    accentSoft: Color(0x2E6E7784),
    bgMid: Color(0xFFF7F8FA),
    bgEdge: Color(0xFFE6E9EE),
    mascotBody: Color(0xFFC2C9D3),
    mood: MascotMood.expired,
  );

  static const urgent = BandPalette(
    accent: Color(0xFFD8431F),
    accentSoft: Color(0x2ED8431F),
    bgMid: Color(0xFFFFF8F5),
    bgEdge: Color(0xFFFFE0D4),
    mascotBody: Color(0xFFFFB3A0),
    mood: MascotMood.urgent,
  );

  static const soon = BandPalette(
    accent: Color(0xFFA8690A),
    accentSoft: Color(0x2EA8690A),
    bgMid: Color(0xFFFFFBF3),
    bgEdge: Color(0xFFFFEDCF),
    mascotBody: Color(0xFFFFD79B),
    mood: MascotMood.soon,
  );

  static const fresh = BandPalette(
    accent: Color(0xFF1B7F43),
    accentSoft: Color(0x2E1B7F43),
    bgMid: Color(0xFFF6FCF8),
    bgEdge: Color(0xFFDAF2E2),
    mascotBody: Color(0xFFAEE8BE),
    mood: MascotMood.fresh,
  );

  static const unknown = BandPalette(
    accent: Color(0xFF5F6A80),
    accentSoft: Color(0x2E5F6A80),
    bgMid: Color(0xFFF8F9FB),
    bgEdge: Color(0xFFE7EAF0),
    mascotBody: Color(0xFFCCD2DE),
    mood: MascotMood.unknown,
  );

  /// 반영 완료. 여유와 같은 색이되 표정이 다르다.
  static const done = BandPalette(
    accent: Color(0xFF1B7F43),
    accentSoft: Color(0x2E1B7F43),
    bgMid: Color(0xFFF3FBF6),
    bgEdge: Color(0xFFD3EFDD),
    mascotBody: Color(0xFFAEE8BE),
    mood: MascotMood.done,
  );

  /// 확인 질문. 챙길 것과 같은 색이되 강조가 더 진하다.
  static const asking = BandPalette(
    accent: Color(0xFF9A5B00),
    accentSoft: Color(0x2E9A5B00),
    bgMid: Color(0xFFFFFAF0),
    bgEdge: Color(0xFFFFE6BA),
    mascotBody: Color(0xFFFFD79B),
    mood: MascotMood.asking,
  );

  /// 목록 화면의 배경.
  ///
  /// 오늘 화면은 등급 색을 입지만 냉장고·기록은 여러 등급을 한 화면에 담는다. 한 등급의
  /// 색을 입히면 나머지가 그 색에 눌린다.
  static const neutral = BandPalette(
    accent: Color(0xFF3F4FD1),
    accentSoft: Color(0x2E3F4FD1),
    bgMid: Color(0xFFF6F7F9),
    bgEdge: Color(0xFFE8EBF0),
    mascotBody: Color(0xFFCCD2DE),
    mood: MascotMood.unknown,
  );

  /// 화면에 나오는 순서. 급한 것이 왼쪽이 아니라, 아치를 따라 지남→여유로 흐른다.
  static const ordered = <Freshness>[
    Freshness.expired,
    Freshness.urgent,
    Freshness.soon,
    Freshness.fresh,
    Freshness.unknown,
  ];

  static BandPalette of(Freshness grade) => switch (grade) {
        Freshness.expired => expired,
        Freshness.urgent => urgent,
        Freshness.soon => soon,
        Freshness.fresh => fresh,
        Freshness.unknown => unknown,
      };
}
