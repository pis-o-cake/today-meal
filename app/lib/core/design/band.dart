/// 신선도 등급과 캐릭터 표정의 정의.
///
/// 목업의 핵심 장치다 — 화면 배경·강조색·캐릭터 색이 **고른 등급**을 따라 함께 바뀐다.
/// 사용자는 앱을 열자마자 색으로 상황을 읽고, 글자로 확인한다.
///
/// 색만으로 구분하지 않는다. 등급마다 문구([Strings])가 항상 함께 나간다.
///
/// **값은 여기 없다.** 화면 테마 4종이 같은 등급을 다른 색으로 그리므로 실제 색은
/// [Skin] 이 갖는다. 이 파일은 등급의 순서와 한 등급이 갖는 색의 **모양**만 정한다.
library;

import 'package:flutter/material.dart';

import '../../domain/model/inventory.dart';

/// 캐릭터 표정.
///
/// 신선도 5종에 음성 상태 3종과 인사를 더한 것이다. 목업 `Mascot2` 의 mood 와 같다.
enum MascotMood {
  expired,
  urgent,
  soon,
  fresh,
  unknown,
  listening,
  asking,
  done,

  /// 스플래시·로그인·마이페이지의 인사 표정.
  hello,
}

/// 한 등급의 배색 묶음.
class BandPalette {
  const BandPalette({
    required this.accent,
    required this.accentBright,
    required this.accentSoft,
    required this.bgMid,
    required this.bgEdge,
    required this.mascotBody,
    required this.mascotDeep,
    required this.mood,
    this.tint,
  });

  /// 등급 이름과 화살표에 쓰는 강조색. 배경 위에서 대비를 확보한 값이다.
  final Color accent;

  /// 같은 색의 밝은 쪽.
  ///
  /// 목업은 **글자에 진한 쪽, 막대·점·파동에 밝은 쪽**을 쓴다. 한 값으로 합치면 글자가
  /// 옅어지거나 막대가 탁해진다.
  final Color accentBright;

  /// 강조색의 옅은 판. 대기 점의 후광과 칩 배경에 쓴다.
  final Color accentSoft;

  /// 배경 그라데이션의 중간 색.
  final Color bgMid;

  /// 배경 그라데이션의 바깥 색. 칩의 옅은 배경으로도 쓴다.
  final Color bgEdge;

  /// 캐릭터 몸 색.
  final Color mascotBody;

  /// 캐릭터의 진한 선·물결 색.
  final Color mascotDeep;

  /// 캐릭터 표정.
  final MascotMood mood;

  /// 화이트 테마에서 화면 꼭대기에만 얇게 도는 색.
  ///
  /// 목업의 화이트 테마는 배경이 거의 평면이고 등급을 **위쪽 옅은 빛**으로만 알린다.
  /// 없으면 완전한 평면 배경을 쓴다(기한 지남·날짜 몰라요).
  final Color? tint;

  /// 두 배색 사이의 중간값.
  ///
  /// 등급을 끄는 동안 화면이 **손가락을 따라** 넘어가게 하려면 중간 상태가 필요하다.
  /// 표정([mood])은 섞을 수 없으므로 절반을 넘긴 쪽을 쓴다.
  static BandPalette lerp(BandPalette a, BandPalette b, double t) => BandPalette(
        accent: Color.lerp(a.accent, b.accent, t)!,
        accentBright: Color.lerp(a.accentBright, b.accentBright, t)!,
        accentSoft: Color.lerp(a.accentSoft, b.accentSoft, t)!,
        bgMid: Color.lerp(a.bgMid, b.bgMid, t)!,
        bgEdge: Color.lerp(a.bgEdge, b.bgEdge, t)!,
        mascotBody: Color.lerp(a.mascotBody, b.mascotBody, t)!,
        mascotDeep: Color.lerp(a.mascotDeep, b.mascotDeep, t)!,
        mood: t < 0.5 ? a.mood : b.mood,
        tint: Color.lerp(a.tint, b.tint, t),
      );
}

/// 등급의 순서. 테마와 무관하다.
abstract final class Bands {
  /// 화면에 나오는 순서.
  ///
  /// 목업의 밴드 순서 그대로다 — 기한 지남에서 시작해 여유로 흐르고, 날짜를 모르는
  /// 것이 맨 끝이다. 내부 키는 바꾸지 않는다.
  static const ordered = <Freshness>[
    Freshness.expired,
    Freshness.urgent,
    Freshness.soon,
    Freshness.fresh,
    Freshness.unknown,
  ];

  /// 재료가 있는 등급 중 처음 보여줄 것을 찾는 순서.
  ///
  /// UI 계약의 「홈 밴드와 재료 타일」이 정한 순서다. 화면에 늘어놓는 순서([ordered])와
  /// 다르다 — 늘어놓는 것은 시간의 흐름이고, 고르는 것은 급한 정도다.
  static const priority = <Freshness>[
    Freshness.urgent,
    Freshness.soon,
    Freshness.expired,
    Freshness.fresh,
    Freshness.unknown,
  ];
}
