import 'package:flutter/material.dart';

import 'breakpoints.dart';
import 'tokens.dart';

/// 폭에 따라 1단과 2단으로 갈리는 배치.
///
/// 핸드폰에서는 [primary] 아래 [secondary] 를 쌓고, 태블릿에서는 나란히 놓는다. 화면마다
/// `LayoutBuilder` 를 다시 쓰지 않도록 여기 한 번만 둔다.
///
/// ```
/// compact                 expanded
/// ┌──────────┐            ┌──────────┬────────┐
/// │ primary  │            │ primary  │ second │
/// ├──────────┤            │          │        │
/// │ secondary│            │          │        │
/// └──────────┘            └──────────┴────────┘
/// ```
class ResponsiveTwoPane extends StatelessWidget {
  const ResponsiveTwoPane({
    required this.primary,
    required this.secondary,
    this.primaryFlex = 3,
    this.secondaryFlex = 2,
    super.key,
  });

  final Widget primary;
  final Widget secondary;
  final int primaryFlex;
  final int secondaryFlex;

  @override
  Widget build(BuildContext context) {
    final form = context.formFactor;
    if (form.columns == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          const SizedBox(height: Tokens.gapCard),
          secondary,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: primaryFlex, child: primary),
        const SizedBox(width: Tokens.gapCard),
        Expanded(flex: secondaryFlex, child: secondary),
      ],
    );
  }
}

/// 본문 폭을 묶고 좌우 여백을 준다.
///
/// 태블릿에서 글줄이 화면 끝까지 늘어나면 읽기 어렵다. 모든 화면이 이 위에 올라간다.
class ContentFrame extends StatelessWidget {
  const ContentFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final gutter =
        context.formFactor.isCompact ? Tokens.gutterCompact : Tokens.gutterWide;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter, vertical: gutter),
          child: child,
        ),
      ),
    );
  }
}
