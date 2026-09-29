/// 화면 테마 4종의 색 정본.
///
/// 목업 `mockup/canvas/*.dc.html` 의 `K` 색 표를 그대로 옮긴 것이다. 목업은 같은 화면을
/// 파스텔·화이트·글래스·다크로 그리며, 사용자가 마이페이지에서 고른다([SkinName]).
///
/// **화면은 색을 직접 적지 않고 `context.skin` 을 읽는다.** 화면마다 값을 다시 적으면
/// 테마를 하나 더 넣을 때 빠뜨리는 화면이 생긴다.
///
/// 등급의 순서와 색의 모양은 [Bands]·[BandPalette] 가 정하고, 실제 값은 여기 있다.
library;

import 'package:flutter/material.dart';

import '../../domain/model/change_record.dart';
import '../../domain/model/inventory.dart';
import 'band.dart';

/// 고를 수 있는 화면 테마.
///
/// 내부 키는 목업의 `theme` prop 과 같다 — 저장값을 목업 파일 이름으로 바로 잇는다.
enum SkinName {
  /// 등급 색이 배경까지 물드는 기본 테마.
  pastel,

  /// 배경을 평면으로 두고 카드만 세우는 테마.
  white,

  /// 흰 유리를 겹쳐 세우는 테마. 흐림과 안쪽 광택을 쓴다.
  glass,

  /// 어두운 테마.
  dark;

  bool get isDark => this == SkinName.dark;
}

/// 기록의 동작 칩 색.
///
/// 동작마다 색이 다르다 — 넣은 것과 뺀 것, 고친 것과 되돌린 것이 한 줄씩 섞여 흐르므로
/// 글자만으로는 훑어지지 않는다. 색만으로 구분하지 않도록 동작 이름을 함께 적는다.
@immutable
class ChipPalette {
  const ChipPalette(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

/// 고른 얼굴 뒤에서 도는 갈기의 색.
///
/// 목업은 이 값을 `hsl` 로 적어 테마 변환에서 빼 두었다 — 등급 색이 아니라 **판의 색**
/// 이므로 밴드가 바뀌어도 같아야 한다.
@immutable
class ManePalette {
  const ManePalette({
    required this.fill,
    required this.stroke,
    required this.shadow,
  });

  /// 꽃잎의 면.
  final Color fill;

  /// 꽃잎의 테두리. 필요 없는 테마에서는 투명이다.
  final Color stroke;

  /// 아래로 떨어지는 그림자.
  final Color shadow;
}

/// 한 테마의 색 묶음.
class Skin {
  const Skin({
    required this.name,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.inkSubtle,
    required this.inkDim,
    required this.glassThin,
    required this.glass,
    required this.glassThick,
    required this.raised,
    required this.edge,
    required this.strong,
    required this.onStrong,
    required this.primary,
    required this.onPrimary,
    required this.field,
    required this.chipNeutral,
    required this.track,
    required this.trackDashed,
    required this.toggleOff,
    required this.toggleOn,
    required this.shadowTint,
    required this.divider,
    required this.hairline,
    required this.mane,
    required this.swatch,
    required this.historyKinds,
    required this.bands,
    required this.listening,
    required this.asking,
    required this.done,
    required this.hello,
    required this.neutral,
    this.sheen,
    this.shadowScale = 1,
  });

  final SkinName name;

  // 글자. 진한 쪽에서 옅은 쪽으로 다섯 단계다.
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color inkSubtle;

  /// 가장 옅은 글자. 개수·단위처럼 곁들이는 값에 쓴다.
  final Color inkDim;

  /// 배경이 많이 비치는 판. 아래 타원 유리면에 쓴다.
  final Color glassThin;

  /// 기본 판. 알약 칩·탭 바에 쓴다.
  final Color glass;

  /// 본문이 올라가는 판. 카드에 쓴다.
  final Color glassThick;

  /// 판 위에 한 겹 더 올라가는 흰 판. 고른 필터·고른 얼굴에 쓴다.
  final Color raised;

  /// 판의 테두리. 밝은 테마에서는 판의 윗면을 세우는 역할이라 거의 흰색이다.
  final Color edge;

  /// 가장 강한 채움. 확인 버튼과 사용자 말풍선에 쓴다.
  final Color strong;

  /// [strong] 위의 글자.
  final Color onStrong;

  /// 계정 화면의 주 행동 색.
  final Color primary;

  /// [primary] 위의 글자.
  final Color onPrimary;

  /// 입력칸 배경.
  final Color field;

  /// 중립 칩의 배경. 보관 위치·종류처럼 등급이 없는 값에 쓴다.
  final Color chipNeutral;

  /// 고른 얼굴 뒤에서 도는 갈기.
  final ManePalette mane;

  /// 마이페이지의 테마 견본에 찍는 점.
  ///
  /// 테마마다 **그 테마를 대표하는 색**이 다르다 — 파스텔은 부드러운 살구, 화이트는 또렷한
  /// 주홍, 글래스와 다크는 파랑이다. 한 밴드의 색으로 통일하면 네 견본이 같은 색이 되어
  /// 무엇이 다른지 보이지 않는다.
  final Color swatch;

  /// 기록의 동작 칩 색. 키는 `Labels.changeAction` 이 쓰는 동작 이름이다.
  final Map<HistoryAction, ChipPalette> historyKinds;

  /// 한 동작의 칩 색. 모르는 동작은 중립으로 둔다.
  ChipPalette historyKind(HistoryAction value) =>
      historyKinds[value] ?? historyKinds[HistoryAction.revert]!;

  /// 막대의 바탕.
  final Color track;

  /// 값을 모를 때의 점선 막대 색.
  final Color trackDashed;

  /// 꺼진 토글의 바탕.
  final Color toggleOff;

  /// 켜진 토글의 바탕.
  final Color toggleOn;

  /// 그림자의 기본 색. 알파는 [shade] 가 곱한다.
  final Color shadowTint;

  /// 카드 사이의 선.
  final Color divider;

  /// 카드 안쪽의 옅은 선.
  final Color hairline;

  /// 등급별 배색.
  final Map<Freshness, BandPalette> bands;

  /// 듣는 중.
  final BandPalette listening;

  /// 확인 질문.
  final BandPalette asking;

  /// 반영 완료.
  final BandPalette done;

  /// 인사. 스플래시·로그인·마이페이지가 쓴다.
  final BandPalette hello;

  /// 등급을 가리지 않는 화면의 배색. 냉장고·기록·마이페이지가 쓴다.
  final BandPalette neutral;

  /// 글래스 테마의 판 광택. 다른 테마는 `null` 이라 단색 판이 된다.
  final Gradient? sheen;

  /// 그림자 알파 배율. 어두운 테마에서 그림자가 보이게 올린다.
  final double shadowScale;

  bool get isDark => name.isDark;

  /// 유리 흐림을 쓰는지. 글래스 테마만 참이다.
  ///
  /// WARNING: `BackdropFilter` 는 비싸다. 테마가 요구할 때만 켠다.
  bool get frosted => name == SkinName.glass;

  BandPalette band(Freshness grade) => bands[grade] ?? neutral;

  /// 판의 단색 채움.
  ///
  /// IMPORTANT: `BoxDecoration` 은 `color` 와 `gradient` 를 함께 가질 수 없다.
  /// 글래스 테마는 광택 그라데이션([sheen])이 면을 대신하므로 단색을 비운다.
  /// 판을 그릴 때는 늘 `color: skin.fillOf(x), gradient: skin.sheen` 쌍으로 쓴다.
  Color? fillOf(Color solid) => sheen == null ? solid : null;

  /// 그림자 한 겹. 알파를 테마 배율로 보정한다.
  BoxShadow shade(double alpha, double blur, double dy) => BoxShadow(
        color: shadowTint.withValues(alpha: (alpha * shadowScale).clamp(0, 1)),
        blurRadius: blur,
        offset: Offset(0, dy),
      );

  /// 떠 있는 판의 그림자.
  List<BoxShadow> get shadowRaised => [shade(0.07, 18, 6)];

  /// 카드의 그림자.
  List<BoxShadow> get shadowCard => [shade(0.08, 24, 8)];

  /// 주 행동의 그림자. 화면에서 가장 앞에 있어야 한다.
  List<BoxShadow> get shadowAction => [shade(0.13, 28, 12), shade(0.06, 5, 2)];

  /// 화면 전체 배경.
  ///
  /// 테마마다 배경이 등급을 말하는 방식이 다르다 — 파스텔은 화면을 물들이고, 화이트는
  /// 꼭대기에만 얇게 비치며, 글래스와 다크는 등급과 무관한 고정 배경이다.
  ///
  /// [focusY] 는 빛의 중심 높이다. CSS `at 50% 20%` 가 `-0.6` 이다.
  Gradient background(BandPalette palette, {double focusY = -0.6}) =>
      switch (name) {
        SkinName.pastel => RadialGradient(
            center: Alignment(0, focusY),
            radius: 1.25,
            colors: [Colors.white, palette.bgMid, palette.bgEdge],
            stops: const [0, 0.42, 1],
          ),
        // 등급 색은 꼭대기에만 8% 로 돈다. 없으면 완전한 평면이다.
        SkinName.white => palette.tint == null
            ? const LinearGradient(colors: [_whiteFlat, _whiteFlat])
            : RadialGradient(
                center: const Alignment(0, -1),
                radius: 1.2,
                colors: [
                  Color.alphaBlend(
                      palette.tint!.withValues(alpha: 0.08), _whiteBase),
                  _whiteBase,
                ],
                stops: const [0, 0.7],
              ),
        SkinName.glass => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFEEF0F4)],
          ),
        SkinName.dark => const LinearGradient(colors: [_darkBase, _darkBase]),
      };

  /// 등급을 가리지 않는 화면의 배경. 빛이 화면 꼭대기에서 온다.
  ///
  /// 냉장고·기록·마이페이지가 쓴다. 파스텔에서도 **차가운** 회색이다 — 목록은 재료의
  /// 등급 색이 주인공이라 배경이 색을 띠면 그 색과 싸운다.
  Gradient get listBackground => background(neutral, focusY: -1);

  /// 조리 화면의 배경. 파스텔에서만 따뜻하다.
  ///
  /// 목업이 조리 탭에만 따뜻한 바탕을 쓴다 — 불과 냄비의 화면이라 차가운 회색이 어울리지
  /// 않는다. 나머지 테마는 목록 화면과 같다.
  Gradient get cookBackground => name == SkinName.pastel
      ? const RadialGradient(
          center: Alignment(0, -1),
          radius: 1.3,
          colors: [Colors.white, Color(0xFFFBF7F4), Color(0xFFF2E9E2)],
          stops: [0, 0.45, 1],
        )
      : listBackground;

  static const _whiteFlat = Color(0xFFF4F5F7);
  static const _whiteBase = Color(0xFFF6F7F9);
  static const _darkBase = Color(0xFF202124);
}

/// 테마 4종의 실제 값.
abstract final class Skins {
  static Skin of(SkinName name) => switch (name) {
        SkinName.pastel => pastel,
        SkinName.white => white,
        SkinName.glass => glass,
        SkinName.dark => dark,
      };

  /// 등급 색이 배경까지 물드는 기본 테마.
  static const pastel = Skin(
    name: SkinName.pastel,
    ink: Color(0xFF15181D),
    inkMuted: Color(0xFF3E454E),
    inkFaint: Color(0xFF5F6670),
    inkSubtle: Color(0xFF6B727B),
    inkDim: Color(0xFF8A9199),
    glassThin: Color(0x9EFFFFFF),
    glass: Color(0xBDFFFFFF),
    glassThick: Color(0xD6FFFFFF),
    raised: Colors.white,
    edge: Color(0xF2FFFFFF),
    strong: Color(0xFF15181D),
    onStrong: Colors.white,
    primary: Color(0xFF4F5FE0),
    onPrimary: Colors.white,
    field: Color(0x80FFFFFF),
    chipNeutral: Color(0xFFEEF0F3),
    track: Color(0xFFEEF0F4),
    trackDashed: Color(0xFFC5CAD3),
    toggleOff: Color(0xFFD5D9E0),
    toggleOn: Color(0xFF5A6BEA),
    shadowTint: Color(0xFF141923),
    divider: Color(0x1A15181D),
    hairline: Color(0x1215181D),
    mane: ManePalette(
      fill: Colors.white,
      stroke: Colors.transparent,
      shadow: Color(0x29141824),
    ),
    swatch: Color(0xFFFFB199),
    historyKinds: {
      HistoryAction.stockIn: ChipPalette(Color(0xFFDDF3E4), Color(0xFF17703C)),
      HistoryAction.consume: ChipPalette(Color(0xFFE4E8FF), Color(0xFF3346B8)),
      HistoryAction.correct: ChipPalette(Color(0xFFFFEBC7), Color(0xFF8F5A08)),
      HistoryAction.revert: ChipPalette(Color(0xFFECEEF2), Color(0xFF4E5661)),
      HistoryAction.adjust: ChipPalette(Color(0xFFF0E6FD), Color(0xFF6B35B0)),
    },
    bands: _pastelBands,
    listening: BandPalette(
      accent: Color(0xFF3F4FD1),
      accentBright: Color(0xFF5A6BEA),
      accentSoft: Color(0x2E5A6BEA),
      bgMid: Color(0xFFF4F5FF),
      bgEdge: Color(0xFFDCE2FF),
      mascotBody: Color(0xFFC7CFFF),
      mascotDeep: Color(0xFF5A6BEA),
      mood: MascotMood.listening,
      tint: Color(0xFF3D5DF5),
    ),
    asking: BandPalette(
      accent: Color(0xFF9A5B00),
      accentBright: Color(0xFFE08E00),
      accentSoft: Color(0x2E9A5B00),
      bgMid: Color(0xFFFFFAF0),
      bgEdge: Color(0xFFFFE6BA),
      mascotBody: Color(0xFFFFE0AA),
      mascotDeep: Color(0xFFE39A2D),
      mood: MascotMood.asking,
      tint: Color(0xFFF5B23D),
    ),
    done: BandPalette(
      accent: Color(0xFF1B7F43),
      accentBright: Color(0xFF23A05A),
      accentSoft: Color(0x2E1B7F43),
      bgMid: Color(0xFFF3FBF6),
      bgEdge: Color(0xFFD3EFDD),
      mascotBody: Color(0xFFBDEBC9),
      mascotDeep: Color(0xFF3FAE5E),
      mood: MascotMood.done,
      tint: Color(0xFF3DF57F),
    ),
    hello: _pastelHello,
    neutral: BandPalette(
      accent: Color(0xFF3F4FD1),
      accentBright: Color(0xFF5A6BEA),
      accentSoft: Color(0x2E3F4FD1),
      bgMid: Color(0xFFF6F6F9),
      bgEdge: Color(0xFFE8EAF0),
      mascotBody: Color(0xFFD9DEE8),
      mascotDeep: Color(0xFF8A94A8),
      mood: MascotMood.unknown,
    ),
  );

  /// 배경을 평면으로 두고 카드만 세우는 테마.
  static const white = Skin(
    name: SkinName.white,
    ink: Color(0xFF15181D),
    inkMuted: Color(0xFF3E454E),
    inkFaint: Color(0xFF5F6670),
    inkSubtle: Color(0xFF6B727B),
    inkDim: Color(0xFF8A9199),
    glassThin: Colors.white,
    glass: Colors.white,
    glassThick: Colors.white,
    raised: Colors.white,
    edge: Color(0x1211141A),
    strong: Color(0xFF15181D),
    onStrong: Colors.white,
    primary: Color(0xFF2B40EE),
    onPrimary: Colors.white,
    field: Colors.white,
    chipNeutral: Color(0xFFEEF0F3),
    track: Color(0xFFEEF0F3),
    trackDashed: Color(0xFFC5CAD3),
    toggleOff: Color(0xFFD5D9E0),
    toggleOn: Color(0xFF2B42EE),
    shadowTint: Color(0xFF141923),
    divider: Color(0x1A15181D),
    hairline: Color(0x1215181D),
    mane: ManePalette(
      fill: Colors.white,
      stroke: Color(0x142B2F3B),
      shadow: Color(0x24141824),
    ),
    swatch: Color(0xFFF24216),
    historyKinds: {
      HistoryAction.stockIn: ChipPalette(Color(0xFFD3F3DD), Color(0xFF0A7D3A)),
      HistoryAction.consume: ChipPalette(Color(0xFFDADFFF), Color(0xFF102AC6)),
      HistoryAction.correct: ChipPalette(Color(0xFFFFE9C2), Color(0xFF8F5A08)),
      HistoryAction.revert: ChipPalette(Color(0xFFECEEF2), Color(0xFF4E5661)),
      HistoryAction.adjust: ChipPalette(Color(0xFFEADBFD), Color(0xFF6010C6)),
    },
    bands: _whiteBands,
    listening: BandPalette(
      accent: Color(0xFF2B40EE),
      accentBright: Color(0xFF4A5CF5),
      accentSoft: Color(0x2E2B40EE),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F3),
      mascotBody: Color(0xFFB0B9F2),
      mascotDeep: Color(0xFF2036DF),
      mood: MascotMood.listening,
      tint: Color(0xFF3D5DF5),
    ),
    asking: BandPalette(
      accent: Color(0xFF8A5200),
      accentBright: Color(0xFFDF9220),
      accentSoft: Color(0x2ED9870D),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F3),
      mascotBody: Color(0xFFF0D3A0),
      mascotDeep: Color(0xFFDF9220),
      mood: MascotMood.asking,
      tint: Color(0xFFF5B23D),
    ),
    done: BandPalette(
      accent: Color(0xFF0C8E40),
      accentBright: Color(0xFF28BD6A),
      accentSoft: Color(0x2E11D45F),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F3),
      mascotBody: Color(0xFFA9E5B9),
      mascotDeep: Color(0xFF35B85A),
      mood: MascotMood.done,
      tint: Color(0xFF3DF57F),
    ),
    hello: _whiteHello,
    neutral: BandPalette(
      accent: Color(0xFF2B40EE),
      accentBright: Color(0xFF4A5CF5),
      accentSoft: Color(0x2E2B40EE),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F3),
      mascotBody: Color(0xFFD9DEE8),
      mascotDeep: Color(0xFF8A94A8),
      mood: MascotMood.unknown,
    ),
  );

  /// 흰 유리를 겹쳐 세우는 테마.
  static const glass = Skin(
    name: SkinName.glass,
    ink: Color(0xFF15181D),
    inkMuted: Color(0xFF3E454E),
    inkFaint: Color(0xFF5F6670),
    inkSubtle: Color(0xFF6B727B),
    inkDim: Color(0xFF8A9199),
    glassThin: Color(0x8AFFFFFF),
    glass: Color(0xA8FFFFFF),
    glassThick: Color(0xC4FFFFFF),
    raised: Color(0xD9FFFFFF),
    edge: Color(0xEBFFFFFF),
    strong: Color(0xFF1D2028),
    onStrong: Colors.white,
    primary: Color(0xFF3649E2),
    onPrimary: Colors.white,
    field: Color(0x9EFFFFFF),
    chipNeutral: Color(0x1A788096),
    track: Color(0x1A788096),
    trackDashed: Color(0x4D788096),
    toggleOff: Color(0x36788096),
    toggleOn: Color(0xFF1D34E2),
    shadowTint: Color(0xFF14192D),
    divider: Color(0x1A15181D),
    hairline: Color(0x0F15181D),
    mane: ManePalette(
      fill: Color(0x8CFFFFFF),
      stroke: Color(0xF2FFFFFF),
      shadow: Color(0x2E242942),
    ),
    swatch: Color(0xFF5B6FEE),
    historyKinds: {
      HistoryAction.stockIn: ChipPalette(Color(0x213CDD6F), Color(0xFF11763B)),
      HistoryAction.consume: ChipPalette(Color(0x211A3BFF), Color(0xFF1D35C9)),
      HistoryAction.correct: ChipPalette(Color(0x21FFAD1A), Color(0xFF8F5A08)),
      HistoryAction.revert: ChipPalette(Color(0x1A788096), Color(0xFF4E5661)),
      HistoryAction.adjust: ChipPalette(Color(0x217F2AEE), Color(0xFF681DC8)),
    },
    bands: _glassBands,
    // 안쪽 광택. 판 위에 한 겹 덮어 유리처럼 세운다.
    sheen: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0x85FFFFFF), Color(0x24FFFFFF), Color(0x4DFFFFFF)],
      stops: [0, 0.5, 1],
    ),
    listening: BandPalette(
      accent: Color(0xFF303EA6),
      accentBright: Color(0xFF3649E2),
      accentSoft: Color(0x2E3649E2),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F4),
      mascotBody: Color(0xFFA0ABEE),
      mascotDeep: Color(0xFF303EA6),
      mood: MascotMood.listening,
    ),
    asking: BandPalette(
      accent: Color(0xFFA67730),
      accentBright: Color(0xFFD9870D),
      accentSoft: Color(0x2ED9870D),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F4),
      mascotBody: Color(0xFFEED2A0),
      mascotDeep: Color(0xFFA67730),
      mood: MascotMood.asking,
    ),
    done: BandPalette(
      accent: Color(0xFF138741),
      accentBright: Color(0xFF19E673),
      accentSoft: Color(0x2E1DC962),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F4),
      mascotBody: Color(0xFFA9E5B9),
      mascotDeep: Color(0xFF30A651),
      mood: MascotMood.done,
    ),
    hello: _glassHello,
    neutral: BandPalette(
      accent: Color(0xFF303EA6),
      accentBright: Color(0xFF3649E2),
      accentSoft: Color(0x2E3649E2),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F4),
      mascotBody: Color(0xFFD9DEE8),
      mascotDeep: Color(0xFF8A94A8),
      mood: MascotMood.unknown,
    ),
  );

  /// 어두운 테마.
  static const dark = Skin(
    name: SkinName.dark,
    ink: Color(0xFFE8EAED),
    inkMuted: Color(0xFFBDC1C6),
    inkFaint: Color(0xFFBDC1C6),
    inkSubtle: Color(0xFF9AA0A6),
    inkDim: Color(0xFF9AA0A6),
    glassThin: Color(0xF52D2E31),
    glass: Color(0xF52D2E31),
    glassThick: Color(0xF52D2E31),
    raised: Color(0xFF3C4043),
    edge: Color(0x14E8EAED),
    strong: Color(0xFFE8EAED),
    onStrong: Color(0xFF202124),
    primary: Color(0xFF8AB4F8),
    onPrimary: Color(0xFF202124),
    field: Color(0xFF2D2E31),
    chipNeutral: Color(0xFF3C4043),
    track: Color(0xFF3C4043),
    trackDashed: Color(0xFF5F6368),
    toggleOff: Color(0xFF5F6368),
    toggleOn: Color(0x998AB4F8),
    shadowTint: Colors.black,
    shadowScale: 1.8,
    divider: Color(0x1FE8EAED),
    hairline: Color(0x1AE8EAED),
    mane: ManePalette(
      fill: Color(0xFF3D4043),
      stroke: Color(0x0FFFFFFF),
      shadow: Color(0x59000000),
    ),
    swatch: Color(0xFF8BB5F8),
    historyKinds: {
      HistoryAction.stockIn: ChipPalette(Color(0x2981C995), Color(0xFF81C995)),
      HistoryAction.consume: ChipPalette(Color(0x298AB4F8), Color(0xFF8AB4F8)),
      HistoryAction.correct: ChipPalette(Color(0x29FCAD70), Color(0xFFFCAD70)),
      HistoryAction.revert: ChipPalette(Color(0xFF3C4043), Color(0xFFBDC1C6)),
      HistoryAction.adjust: ChipPalette(Color(0x29C58AF9), Color(0xFFC58AF9)),
    },
    bands: _darkBands,
    listening: BandPalette(
      accent: Color(0xFF8AB4F8),
      accentBright: Color(0xFF8AB4F8),
      accentSoft: Color(0x388AB4F8),
      bgMid: Color(0xFF202124),
      bgEdge: Color(0xFF3C4043),
      mascotBody: Color(0xFFC7CFFF),
      mascotDeep: Color(0xFF5A6BEA),
      mood: MascotMood.listening,
    ),
    asking: BandPalette(
      accent: Color(0xFFFCAD70),
      accentBright: Color(0xFFFCAD70),
      accentSoft: Color(0x38FCAD70),
      bgMid: Color(0xFF202124),
      bgEdge: Color(0xFF3C4043),
      mascotBody: Color(0xFFFFE0AA),
      mascotDeep: Color(0xFFE39A2D),
      mood: MascotMood.asking,
    ),
    done: BandPalette(
      accent: Color(0xFF81C995),
      accentBright: Color(0xFF81C995),
      accentSoft: Color(0x3881C995),
      bgMid: Color(0xFF202124),
      bgEdge: Color(0xFF3C4043),
      mascotBody: Color(0xFFBDEBC9),
      mascotDeep: Color(0xFF3FAE5E),
      mood: MascotMood.done,
    ),
    hello: _darkHello,
    neutral: BandPalette(
      accent: Color(0xFF8AB4F8),
      accentBright: Color(0xFF8AB4F8),
      accentSoft: Color(0x388AB4F8),
      bgMid: Color(0xFF202124),
      bgEdge: Color(0xFF3C4043),
      mascotBody: Color(0xFFD9DEE8),
      mascotDeep: Color(0xFF8A94A8),
      mood: MascotMood.unknown,
    ),
  );

  // 인사 표정. 듣는 중과 같은 몸 색에 웃는 얼굴이다.
  static const _pastelHello = BandPalette(
    accent: Color(0xFF3F4FD1),
    accentBright: Color(0xFF5A6BEA),
    accentSoft: Color(0x2E5A6BEA),
    bgMid: Color(0xFFF6F7FF),
    bgEdge: Color(0xFFE1E6FF),
    mascotBody: Color(0xFFC7CFFF),
    mascotDeep: Color(0xFF5A6BEA),
    mood: MascotMood.hello,
    tint: Color(0xFF3D5CF5),
  );

  static const _whiteHello = BandPalette(
    accent: Color(0xFF2B40EE),
    accentBright: Color(0xFF4A5CF5),
    accentSoft: Color(0x2E2B40EE),
    bgMid: Colors.white,
    bgEdge: Color(0xFFEEF0F3),
    mascotBody: Color(0xFFB0B9F2),
    mascotDeep: Color(0xFF2036DF),
    mood: MascotMood.hello,
    tint: Color(0xFF3D5CF5),
  );

  static const _glassHello = BandPalette(
    accent: Color(0xFF303EA6),
    accentBright: Color(0xFF3649E2),
    accentSoft: Color(0x2E3649E2),
    bgMid: Colors.white,
    bgEdge: Color(0xFFEEF0F4),
    mascotBody: Color(0xFFA0ABEE),
    mascotDeep: Color(0xFF303EA6),
    mood: MascotMood.hello,
  );

  static const _darkHello = BandPalette(
    accent: Color(0xFF8AB4F8),
    accentBright: Color(0xFF8AB4F8),
    accentSoft: Color(0x388AB4F8),
    bgMid: Color(0xFF202124),
    bgEdge: Color(0xFF3C4043),
    mascotBody: Color(0xFFC7CFFF),
    mascotDeep: Color(0xFF5A6BEA),
    mood: MascotMood.hello,
  );

  static const _pastelBands = <Freshness, BandPalette>{
    Freshness.expired: BandPalette(
      accent: Color(0xFF6E7784),
      accentBright: Color(0xFF8C95A3),
      accentSoft: Color(0x246E7784),
      bgMid: Color(0xFFF7F8FA),
      bgEdge: Color(0xFFE6E9EE),
      mascotBody: Color(0xFFD5DAE1),
      mascotDeep: Color(0xFF8C95A3),
      mood: MascotMood.expired,
    ),
    Freshness.urgent: BandPalette(
      accent: Color(0xFFD8431F),
      accentBright: Color(0xFFE8573A),
      accentSoft: Color(0x24D8431F),
      bgMid: Color(0xFFFFF8F5),
      bgEdge: Color(0xFFFFE0D4),
      mascotBody: Color(0xFFFFC2B2),
      mascotDeep: Color(0xFFE8573A),
      mood: MascotMood.urgent,
      tint: Color(0xFFF5703D),
    ),
    Freshness.soon: BandPalette(
      accent: Color(0xFFA8690A),
      accentBright: Color(0xFFE08E00),
      accentSoft: Color(0x24A8690A),
      bgMid: Color(0xFFFFFBF3),
      bgEdge: Color(0xFFFFEDCF),
      mascotBody: Color(0xFFFFE0AA),
      mascotDeep: Color(0xFFE39A2D),
      mood: MascotMood.soon,
      tint: Color(0xFFF5B03D),
    ),
    Freshness.fresh: BandPalette(
      accent: Color(0xFF1B7F43),
      accentBright: Color(0xFF23A05A),
      accentSoft: Color(0x241B7F43),
      bgMid: Color(0xFFF6FCF8),
      bgEdge: Color(0xFFDAF2E2),
      mascotBody: Color(0xFFBDEBC9),
      mascotDeep: Color(0xFF3FAE5E),
      mood: MascotMood.fresh,
      tint: Color(0xFF3DF57A),
    ),
    Freshness.unknown: BandPalette(
      accent: Color(0xFF5F6A80),
      accentBright: Color(0xFF8A94A8),
      accentSoft: Color(0x295F6A80),
      bgMid: Color(0xFFF8F9FB),
      bgEdge: Color(0xFFE7EAF0),
      mascotBody: Color(0xFFD9DEE8),
      mascotDeep: Color(0xFF8A94A8),
      mood: MascotMood.unknown,
    ),
  };

  static const _whiteBands = <Freshness, BandPalette>{
    Freshness.expired: BandPalette(
      accent: Color(0xFF6E7784),
      accentBright: Color(0xFF8C95A3),
      accentSoft: Color(0x246E7784),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F3),
      mascotBody: Color(0xFFD5DAE1),
      mascotDeep: Color(0xFF8C95A3),
      mood: MascotMood.expired,
    ),
    Freshness.urgent: BandPalette(
      accent: Color(0xFFC63310),
      accentBright: Color(0xFFDF4020),
      accentSoft: Color(0x24E43B13),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F3),
      mascotBody: Color(0xFFF1B6A7),
      mascotDeep: Color(0xFFDF4020),
      mood: MascotMood.urgent,
      tint: Color(0xFFF5703D),
    ),
    Freshness.soon: BandPalette(
      accent: Color(0xFFA8690A),
      accentBright: Color(0xFFDF9220),
      accentSoft: Color(0x24D9870D),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F3),
      mascotBody: Color(0xFFF0D3A0),
      mascotDeep: Color(0xFFDF9220),
      mood: MascotMood.soon,
      tint: Color(0xFFF5B03D),
    ),
    Freshness.fresh: BandPalette(
      accent: Color(0xFF0C8E40),
      accentBright: Color(0xFF35B85A),
      accentSoft: Color(0x2411D45F),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F3),
      mascotBody: Color(0xFFA9E5B9),
      mascotDeep: Color(0xFF35B85A),
      mood: MascotMood.fresh,
      tint: Color(0xFF3DF57A),
    ),
    Freshness.unknown: BandPalette(
      accent: Color(0xFF5F6A80),
      accentBright: Color(0xFF8A94A8),
      accentSoft: Color(0x295F6A80),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F3),
      mascotBody: Color(0xFFD9DEE8),
      mascotDeep: Color(0xFF8A94A8),
      mood: MascotMood.unknown,
    ),
  };

  static const _glassBands = <Freshness, BandPalette>{
    Freshness.expired: BandPalette(
      accent: Color(0xFF6E7784),
      accentBright: Color(0xFF8C95A3),
      accentSoft: Color(0x246E7784),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F4),
      mascotBody: Color(0xFFD5DAE1),
      mascotDeep: Color(0xFF8C95A3),
      mood: MascotMood.expired,
    ),
    Freshness.urgent: BandPalette(
      accent: Color(0xFFC93E1D),
      accentBright: Color(0xFFA64430),
      accentSoft: Color(0x24D8431F),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F4),
      mascotBody: Color(0xFFEEB0A0),
      mascotDeep: Color(0xFFA64430),
      mood: MascotMood.urgent,
    ),
    Freshness.soon: BandPalette(
      accent: Color(0xFFA8690A),
      accentBright: Color(0xFFA67730),
      accentSoft: Color(0x24D9870D),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F4),
      mascotBody: Color(0xFFEED2A0),
      mascotDeep: Color(0xFFA67730),
      mood: MascotMood.soon,
    ),
    Freshness.fresh: BandPalette(
      accent: Color(0xFF138741),
      accentBright: Color(0xFF30A651),
      accentSoft: Color(0x241DC962),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F4),
      mascotBody: Color(0xFFA9E5B9),
      mascotDeep: Color(0xFF30A651),
      mood: MascotMood.fresh,
    ),
    Freshness.unknown: BandPalette(
      accent: Color(0xFF5F6A80),
      accentBright: Color(0xFF8A94A8),
      accentSoft: Color(0x295F6A80),
      bgMid: Colors.white,
      bgEdge: Color(0xFFEEF0F4),
      mascotBody: Color(0xFFD9DEE8),
      mascotDeep: Color(0xFF8A94A8),
      mood: MascotMood.unknown,
    ),
  };

  // 다크 테마의 `bgEdge` 는 배경이 아니라 **칩의 면**이다. 배경은 등급과 무관하게
  // 평면이므로(`Skin.background`), 여기 값은 칩과 막대에만 쓰인다.
  static const _darkBands = <Freshness, BandPalette>{
    Freshness.expired: BandPalette(
      accent: Color(0xFF9AA0A6),
      accentBright: Color(0xFF9AA0A6),
      accentSoft: Color(0x2B9AA0A6),
      bgMid: Color(0xFF202124),
      bgEdge: Color(0xFF3C4043),
      mascotBody: Color(0xFFD5DAE1),
      mascotDeep: Color(0xFF8C95A3),
      mood: MascotMood.expired,
    ),
    Freshness.urgent: BandPalette(
      accent: Color(0xFFF28B82),
      accentBright: Color(0xFFF28B82),
      accentSoft: Color(0x2BF28B82),
      bgMid: Color(0xFF202124),
      bgEdge: Color(0xFF4A3330),
      mascotBody: Color(0xFFFFC2B2),
      mascotDeep: Color(0xFFE8573A),
      mood: MascotMood.urgent,
    ),
    Freshness.soon: BandPalette(
      accent: Color(0xFFFCAD70),
      accentBright: Color(0xFFFCAD70),
      accentSoft: Color(0x2BFCAD70),
      bgMid: Color(0xFF202124),
      bgEdge: Color(0xFF4A3D2E),
      mascotBody: Color(0xFFFFE0AA),
      mascotDeep: Color(0xFFE39A2D),
      mood: MascotMood.soon,
    ),
    Freshness.fresh: BandPalette(
      accent: Color(0xFF81C995),
      accentBright: Color(0xFF81C995),
      accentSoft: Color(0x2B81C995),
      bgMid: Color(0xFF202124),
      bgEdge: Color(0xFF2C3E32),
      mascotBody: Color(0xFFBDEBC9),
      mascotDeep: Color(0xFF3FAE5E),
      mood: MascotMood.fresh,
    ),
    Freshness.unknown: BandPalette(
      accent: Color(0xFFBDC1C6),
      accentBright: Color(0xFFBDC1C6),
      accentSoft: Color(0x2BBDC1C6),
      bgMid: Color(0xFF202124),
      bgEdge: Color(0xFF3C4043),
      mascotBody: Color(0xFFD9DEE8),
      mascotDeep: Color(0xFF8A94A8),
      mood: MascotMood.unknown,
    ),
  };
}

/// 화면 테마를 아래로 내린다.
///
/// `Provider` 가 아니라 [InheritedWidget] 인 이유는, 색은 **모든 위젯이 읽고 아무도
/// 쓰지 않는** 값이기 때문이다. 구독 대상을 따로 두면 테마를 바꿀 때 화면이 두 번 그려진다.
class SkinScope extends InheritedWidget {
  const SkinScope({required this.skin, required super.child, super.key});

  final Skin skin;

  static Skin? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SkinScope>()?.skin;

  @override
  bool updateShouldNotify(SkinScope old) => old.skin.name != skin.name;
}

/// 현재 테마.
extension SkinContext on BuildContext {
  /// 이 화면의 색.
  ///
  /// 감싸는 [SkinScope] 가 없으면 기본 테마를 쓴다. 화면 하나만 떼어 위젯 테스트하는
  /// 경우를 위한 것이며, 앱에서는 [SkinScope] 가 언제나 있다.
  Skin get skin => SkinScope.maybeOf(this) ?? Skins.pastel;
}
