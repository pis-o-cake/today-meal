import 'package:flutter/material.dart';

import '../../core/design/responsive.dart';
import '../../core/design/tokens.dart';
import '../../core/di.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/menu.dart';
import '../../domain/repository/repositories.dart';

/// 메뉴 상세.
///
/// 인분에 맞춘 재료와 조리 순서를 보여준다. **조회만으로 재고를 바꾸지 않는다** —
/// 반영은 "해먹었어요"를 눌렀을 때만 일어난다.
///
/// 분량을 모르는 재료는 환산하지 않고 그대로 둔다. 숫자를 지어내지 않는다.
class MenuDetailScreen extends StatefulWidget {
  const MenuDetailScreen({required this.recipeId, this.servings, super.key});

  final int recipeId;
  final int? servings;

  @override
  State<MenuDetailScreen> createState() => _MenuDetailScreenState();
}

class _MenuDetailScreenState extends State<MenuDetailScreen> {
  MenuDetail? _detail;
  Object? _error;
  late int _servings = widget.servings ?? 2;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail =
          await di<MenuRepository>().detail(widget.recipeId, servings: _servings);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _changeServings(int next) {
    setState(() => _servings = next);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(title: Text(detail?.name ?? '')),
      body: SafeArea(
        child: _error != null
            ? Center(child: Text('$_error'))
            : detail == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      ContentFrame(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Head(detail: detail, onServings: _changeServings),
                            const SizedBox(height: Tokens.gapCard),
                            _Ingredients(detail: detail),
                            const SizedBox(height: Tokens.gapCard),
                            _Steps(detail: detail),
                            const SizedBox(height: Tokens.gapCard),
                            FilledButton(
                              // TODO: S-08 후속 — "해먹었어요" 로 사용량을 반영한다.
                              //  중복 차감은 서버의 consumption_applied 가 막는다.
                              onPressed: null,
                              child: const Text(Strings.menuCooked),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.detail, required this.onServings});

  final MenuDetail detail;
  final ValueChanged<int> onServings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(detail.name, style: theme.textTheme.displaySmall),
        const SizedBox(height: Tokens.gapTight),
        Wrap(
          spacing: Tokens.gapTight,
          children: [
            Text(Strings.menuServings(detail.servings),
                style: theme.textTheme.labelLarge),
            if (detail.estimatedMinutes != null)
              Text(Strings.menuMinutes(detail.estimatedMinutes!),
                  style: theme.textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: Tokens.gapTight),
        Wrap(
          spacing: Tokens.gapTight,
          children: [
            for (final n in [1, 2, 3, 4])
              ChoiceChip(
                label: Text(Strings.menuServings(n)),
                selected: detail.servings == n,
                onSelected: (_) => onServings(n),
              ),
          ],
        ),
      ],
    );
  }
}

class _Ingredients extends StatelessWidget {
  const _Ingredients({required this.detail});

  final MenuDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.gapCard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Strings.menuIngredients, style: theme.textTheme.titleLarge),
            const SizedBox(height: Tokens.gapCard),
            for (final item in detail.ingredients)
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.gapTight),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          // 필수 재료를 구분한다. 없으면 요리가 성립하지 않는다.
                          fontWeight:
                              item.isEssential ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    Text(
                      // 분량을 모르면 숫자를 만들지 않는다.
                      item.requiredAmount == null
                          ? Strings.quantityUnknown
                          : '${item.requiredAmount}${item.unit ?? ''}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(width: Tokens.gapTight),
                    _StatusDot(status: item.status),
                  ],
                ),
              ),
            const SizedBox(height: Tokens.gapTight),
            Wrap(
              spacing: Tokens.gapTight,
              children: [
                // TODO: S-13 — 부족 재료의 쿠팡 검색으로 잇는다.
                TextButton(onPressed: null, child: const Text(Strings.menuFindOnCoupang)),
                TextButton(onPressed: null, child: const Text(Strings.menuSubstitute)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final IngredientStatus status;

  @override
  Widget build(BuildContext context) {
    // 색만으로 구분하지 않는다. 아이콘 모양도 함께 바꾼다.
    final (icon, color) = switch (status) {
      IngredientStatus.have => (Icons.check_circle_outline, Tokens.lime),
      IngredientStatus.needsCheck => (Icons.help_outline, Tokens.warm),
      IngredientStatus.missing => (Icons.remove_circle_outline, Tokens.alert),
    };
    return Icon(icon, size: 18, color: color);
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.detail});

  final MenuDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.gapCard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Strings.menuSteps, style: theme.textTheme.titleLarge),
            const SizedBox(height: Tokens.gapCard),
            for (final (index, step) in detail.steps.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.gapTight),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text('${index + 1}.',
                          style: theme.textTheme.bodyLarge),
                    ),
                    Expanded(
                      child: Text(step, style: theme.textTheme.bodyLarge),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
