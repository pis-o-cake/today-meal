/// 목업의 반복 부품.
///
/// 반투명 판·알약 칩·입력칸. 화면마다 `BoxDecoration` 을 다시 쓰면 값이 흩어져 판끼리
/// 미묘하게 달라진다.
///
/// 색은 [Skin] 이 정한다. **글래스 테마에서만** 흐림과 안쪽 광택을 켠다 —
/// `BackdropFilter` 는 비싸서 모든 테마에 걸면 목록이 버벅인다.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import '../../domain/model/inventory.dart';

/// 판의 두께. 테마가 실제 색을 정한다.
enum GlassWeight {
  /// 배경이 많이 비친다. 아래 타원 유리면.
  thin,

  /// 기본. 알약 칩·탭 바.
  base,

  /// 본문이 올라가는 카드.
  thick;

  /// 이 두께의 실제 채움.
  ///
  /// 두께를 [Skin] 이 아니라 여기서 푸는 이유는, 두께가 **화면이 고르는 표현**이고
  /// 색이 테마가 정하는 값이라 둘의 방향이 반대이기 때문이다.
  ///
  /// 글래스 테마에서는 `null` 이다 — 광택 그라데이션이 면을 대신하며, 단색과 함께
  /// 주면 `BoxDecoration` 이 거부한다([Skin.fillOf]).
  Color? of(Skin skin) => skin.fillOf(switch (this) {
        GlassWeight.thin => skin.glassThin,
        GlassWeight.base => skin.glass,
        GlassWeight.thick => skin.glassThick,
      });
}

/// 배경 위에 떠 있는 반투명 판.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = Tokens.radiusCard,
    this.weight = GlassWeight.base,
    this.shadow,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final GlassWeight weight;

  /// 그림자를 직접 줄 때. 없으면 테마의 카드 그림자를 쓴다.
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Frosted(
      radius: radius,
      skin: skin,
      shadow: shadow ?? skin.shadowCard,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: weight.of(skin),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: skin.edge),
          gradient: skin.sheen,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 알약 모양 판. 상태 표시줄·버튼처럼 완전히 둥근 판에 쓴다.
class GlassPill extends StatelessWidget {
  const GlassPill({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
    this.weight = GlassWeight.base,
    this.shadow,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final GlassWeight weight;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Frosted(
      shape: const StadiumBorder(),
      skin: skin,
      shadow: shadow ?? skin.shadowRaised,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: weight.of(skin),
          shape: StadiumBorder(side: BorderSide(color: skin.edge)),
          gradient: skin.sheen,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 유리 흐림과 그림자를 판 뒤에 깐다.
///
/// 흐림은 글래스 테마에서만 켠다. 그림자는 흐림 밖에 있어야 한다 — `BackdropFilter`
/// 안에 두면 자기 그림자까지 흐려 테두리가 번진다.
class Frosted extends StatelessWidget {
  const Frosted({
    required this.child,
    required this.skin,
    required this.shadow,
    this.radius,
    this.shape,
    super.key,
  });

  final Widget child;
  final Skin skin;
  final List<BoxShadow> shadow;
  final double? radius;
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) {
    final border = shape ?? RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius ?? Tokens.radiusCard));
    final body = skin.frosted
        ? ClipPath(
            clipper: ShapeBorderClipper(shape: border),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: child,
            ),
          )
        : child;

    return DecoratedBox(
      decoration: ShapeDecoration(shape: border, shadows: shadow),
      child: body,
    );
  }
}

/// 작은 정보 칩. 기한·보관 위치처럼 짧은 값에 쓴다.
class InfoChip extends StatelessWidget {
  const InfoChip({
    required this.label,
    this.background,
    this.foreground,
    this.icon,
    super.key,
  });

  final String label;

  /// 없으면 테마의 중립 칩 색을 쓴다.
  final Color? background;
  final Color? foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final icon = this.icon;
    final fg = foreground ?? skin.inkMuted;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? skin.chipNeutral,
        borderRadius: BorderRadius.circular(Tokens.radiusChip),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 재료 이름처럼 배경 위에 떠 있는 옅은 칩.
class FloatingChip extends StatelessWidget {
  const FloatingChip({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Frosted(
      shape: const StadiumBorder(),
      skin: skin,
      shadow: [skin.shade(0.05, 8, 2)],
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: GlassWeight.base.of(skin),
          shape: StadiumBorder(side: BorderSide(color: skin.edge)),
          gradient: skin.sheen,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: skin.inkMuted, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// 계정 화면의 입력칸.
///
/// 오류는 **그 칸에 붙여** 보여준다 — UI 계약대로 어떤 칸이 틀렸는지 바로 보여야 한다.
/// 이름 옆이 아니라 칸 아래에 두는 이유는, 옆에 두면 "이메일이나 비밀번호가 맞지
/// 않아요" 같은 문장이 잘리기 때문이다. 잘린 오류는 없는 것보다 나쁘다.
///
/// 비밀번호는 로그로 남기지 않는다.
class GlassField extends StatelessWidget {
  const GlassField({
    required this.label,
    required this.controller,
    this.hint,
    this.error,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.trailing,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? error;
  final bool obscure;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final invalid = error != null && error!.isNotEmpty;
    final danger = skin.band(Freshness.urgent).accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            label,
            style: text.labelMedium
                ?.copyWith(color: skin.inkMuted, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        Stack(
          children: [
            TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              autofillHints: autofillHints,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: text.bodyLarge?.copyWith(fontSize: 16, color: skin.ink),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: text.bodyLarge?.copyWith(fontSize: 16, color: skin.inkDim),
                filled: true,
                fillColor: skin.field,
                isDense: true,
                contentPadding: EdgeInsets.only(
                    left: 16, right: trailing == null ? 16 : 52, top: 15, bottom: 15),
                border: _border(skin.edge),
                enabledBorder: _border(invalid ? danger : skin.edge),
                focusedBorder: _border(invalid ? danger : skin.primary, width: 1.6),
              ),
            ),
            if (trailing != null)
              Positioned(right: 3, top: 3, bottom: 3, child: trailing!),
          ],
        ),
        // 잘리지 않게 폭을 다 쓰고 줄을 넘긴다.
        if (invalid)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              error!,
              style: text.labelMedium?.copyWith(color: danger),
            ),
          ),
      ],
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusField),
        borderSide: BorderSide(color: color, width: width),
      );
}
