/// 마이페이지 (UI-11).
///
/// 목업 `MyPage.dc.html` 이다 — 프로필, 화면 테마, 음성·식사·알림 설정, 로그아웃.
///
/// **실제 닉네임과 로그인 경로를 표시한다.** 목업의 "철님", "카카오 계정"을 하드코딩하지
/// 않는다. 게스트는 게스트라고 적고 로그인 진입을 준다.
///
/// 음성 응답 토글은 TTS 만 제어한다 — 마이크 음소거와 다른 설정이다. 기한 알림은 앱 안의
/// 표시이며 OS 푸시가 아니다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/band.dart';
import '../../core/design/labels.dart';
import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../core/settings/app_settings.dart';
import '../../domain/model/inventory.dart';
import '../widgets/glass.dart';
import '../widgets/mascot.dart';
import '../widgets/screen_scaffold.dart';

class MyPageScreen extends StatelessWidget {
  const MyPageScreen({
    required this.onSignIn,
    required this.onSignOut,
    super.key,
  });

  /// 게스트가 로그인 화면으로 간다.
  final VoidCallback onSignIn;

  /// 세션을 끝내고 로그인 화면으로 간다.
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final skin = context.skin;
    final text = Theme.of(context).textTheme;

    return ListScreen(
      header: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(Strings.myPageTitle, style: text.headlineMedium),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 108),
        children: [
          _Profile(
            account: settings.account,
            skin: skin,
            onSignIn: onSignIn,
          ),
          const SizedBox(height: 18),
          _Section(
            title: Strings.myPageThemeSection,
            skin: skin,
            child: _ThemePicker(current: settings.skin, onPick: settings.chooseSkin),
          ),
          const SizedBox(height: 18),
          _Section(
            title: Strings.myPageVoiceSection,
            skin: skin,
            padded: false,
            child: _Rows(
              skin: skin,
              rows: [
                _Row.value(
                  label: Strings.wakeWordSetting,
                  value: Strings.wakeWord,
                  onTap: null,
                ),
                _Row.toggle(
                  label: Strings.myPageSpokenReply,
                  on: settings.spokenReply,
                  onChanged: settings.setSpokenReply,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _Section(
            title: Strings.myPageMealSection,
            skin: skin,
            padded: false,
            child: _Rows(
              skin: skin,
              rows: [
                _Row.stepper(
                  label: Strings.myPageDefaultServings,
                  value: settings.defaultServings,
                  onChanged: settings.setDefaultServings,
                ),
                // 아직 화면이 없는 항목은 값 대신 그 사실을 적는다.
                _Row.value(
                  label: Strings.myPagePantryStaples,
                  value: Strings.settingPending,
                  onTap: null,
                ),
                _Row.value(
                  label: Strings.myPageAvoided,
                  value: Strings.settingPending,
                  onTap: null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _Section(
            title: Strings.myPageAlertSection,
            skin: skin,
            padded: false,
            child: _Rows(
              skin: skin,
              rows: [
                _Row.toggle(
                  label: Strings.myPageExpiryAlert,
                  on: settings.expiryAlert,
                  onChanged: settings.setExpiryAlert,
                ),
                _Row.value(
                  label: Strings.myPageAlertTiming,
                  value: Strings.settingPending,
                  onTap: null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _Section(
            title: Strings.myPageAccountSection,
            skin: skin,
            padded: false,
            child: _Rows(
              skin: skin,
              rows: [
                _Row.value(
                  label: Strings.myPageSignOut,
                  value: '',
                  danger: true,
                  onTap: onSignOut,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 프로필. 게스트와 로그인한 사람을 구분한다.
class _Profile extends StatelessWidget {
  const _Profile({
    required this.account,
    required this.skin,
    required this.onSignIn,
  });

  final Account? account;
  final Skin skin;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final guest = account == null || account!.isGuest;
    final name = guest
        ? Strings.myPageGuestKitchen
        : Strings.myPageKitchen(account!.nickname);
    final under = guest
        ? Strings.myPageGuestHint
        : Strings.myPageSignedInWith(Labels.provider(account!.provider));

    return GlassPanel(
      weight: GlassWeight.thick,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      shadow: [skin.shade(0.08, 24, 8)],
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: skin.hello.accentSoft,
              borderRadius: BorderRadius.circular(Tokens.radiusTile),
            ),
            alignment: Alignment.center,
            child: const Mascot(mood: MascotMood.hello, size: 54),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleLarge?.copyWith(fontSize: 19)),
                const SizedBox(height: 3),
                Text(
                  under,
                  maxLines: 2,
                  style: text.labelMedium
                      ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          if (guest)
            TextButton(
              onPressed: onSignIn,
              style: TextButton.styleFrom(minimumSize: const Size(0, Tokens.tap)),
              child: Text(
                Strings.myPageSignIn,
                style: text.bodyMedium
                    ?.copyWith(color: skin.primary, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.skin,
    required this.child,
    this.padded = true,
  });

  final String title;
  final Skin skin;
  final Widget child;

  /// 판 안쪽에 여백을 줄지. 줄 목록은 줄마다 여백을 가져 끈다.
  final bool padded;

  @override
  Widget build(BuildContext context) => Semantics(
        label: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: skin.inkSubtle, fontWeight: FontWeight.w700),
              ),
            ),
            GlassPanel(
              radius: Tokens.radiusPanel,
              weight: GlassWeight.thick,
              padding: padded ? const EdgeInsets.all(12) : EdgeInsets.zero,
              shadow: [skin.shade(0.06, 24, 8)],
              child: child,
            ),
          ],
        ),
      );
}

/// 화면 테마 고르기. 견본은 각 테마의 실제 배경과 카드 색을 쓴다.
class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.current, required this.onPick});

  final SkinName current;
  final Future<void> Function(SkinName next) onPick;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Semantics(
      label: Strings.myPageThemeSection,
      child: Row(
        children: [
          for (final name in SkinName.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _Swatch(
                  name: name,
                  on: name == current,
                  frame: skin,
                  onTap: () => onPick(name),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.name,
    required this.on,
    required this.frame,
    required this.onTap,
  });

  final SkinName name;
  final bool on;

  /// 지금 쓰고 있는 테마. 테두리와 글자에 쓴다.
  final Skin frame;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 견본은 **그 테마의 실제 값**으로 그린다. 따로 색을 적으면 실제와 달라진다.
    final sample = Skins.of(name);
    final text = Theme.of(context).textTheme;

    return Semantics(
      selected: on,
      label: Labels.skinName(name),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              height: 54,
              decoration: BoxDecoration(
                // 중립 배경은 네 테마가 거의 같다. 스플래시·로그인에서 실제로 보는
                // 진입 배색을 견본으로 써야 고를 때 차이가 읽힌다.
                gradient: sample.background(sample.hello, focusY: -0.7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: on ? frame.hello.accentBright : sample.edge,
                  width: on ? 2.5 : 1,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 11,
                    top: 10,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: sample.band(Freshness.urgent).accentBright,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 9,
                    right: 9,
                    bottom: 9,
                    child: Container(
                      height: 15,
                      decoration: BoxDecoration(
                        color: sample.glassThick,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              Labels.skinName(name),
              style: text.labelMedium?.copyWith(
                color: on ? frame.ink : frame.inkFaint,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 설정 줄 하나.
class _Row {
  const _Row.value({
    required this.label,
    required this.value,
    required this.onTap,
    this.danger = false,
  })  : kind = _RowKind.value,
        on = false,
        number = 0,
        onChanged = null,
        onNumber = null;

  const _Row.toggle({
    required this.label,
    required this.on,
    required ValueChanged<bool> onChanged,
  })  : kind = _RowKind.toggle,
        value = '',
        danger = false,
        number = 0,
        onTap = null,
        onNumber = null,
        // ignore: prefer_initializing_formals
        onChanged = onChanged;

  const _Row.stepper({
    required this.label,
    required int value,
    required ValueChanged<int> onChanged,
  })  : kind = _RowKind.stepper,
        number = value,
        value = '',
        danger = false,
        on = false,
        onTap = null,
        onChanged = null,
        onNumber = onChanged;

  final _RowKind kind;
  final String label;
  final String value;
  final bool on;
  final int number;
  final bool danger;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onChanged;
  final ValueChanged<int>? onNumber;
}

enum _RowKind { value, toggle, stepper }

class _Rows extends StatelessWidget {
  const _Rows({required this.rows, required this.skin});

  final List<_Row> rows;
  final Skin skin;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final (index, row) in rows.indexed) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(height: 1, color: skin.hairline),
              ),
            _RowTile(row: row, skin: skin),
          ],
        ],
      );
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, required this.skin});

  final _Row row;
  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final label = Expanded(
      child: Text(
        row.label,
        style: text.titleSmall?.copyWith(
          color: row.danger ? skin.band(Freshness.urgent).accent : skin.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Row(
          children: [
            label,
            switch (row.kind) {
              _RowKind.toggle => _Switch(
                  on: row.on,
                  label: row.label,
                  skin: skin,
                  onChanged: row.onChanged!,
                ),
              _RowKind.stepper => _Stepper(
                  value: row.number,
                  label: row.label,
                  skin: skin,
                  onChanged: row.onNumber!,
                ),
              _RowKind.value => Row(
                  children: [
                    Text(
                      row.value,
                      style: text.bodyLarge?.copyWith(
                          color: skin.inkFaint, fontWeight: FontWeight.w500),
                    ),
                    if (row.onTap != null) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward_ios_rounded,
                          size: 16, color: skin.inkDim),
                    ],
                  ],
                ),
            },
          ],
        ),
      ),
    );

    if (row.onTap == null) return body;
    return InkWell(onTap: row.onTap, child: body);
  }
}

/// 목업의 토글. 노브가 미끄러진다.
class _Switch extends StatelessWidget {
  const _Switch({
    required this.on,
    required this.label,
    required this.skin,
    required this.onChanged,
  });

  final bool on;
  final String label;
  final Skin skin;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: on,
        label: label,
        child: GestureDetector(
          onTap: () => onChanged(!on),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 52,
            height: 32,
            decoration: BoxDecoration(
              color: on ? skin.toggleOn : skin.toggleOff,
              borderRadius: BorderRadius.circular(16),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [skin.shade(0.2, 6, 2)],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// 기본 인분. 목업에는 값만 있지만 고칠 화면이 따로 없어 여기서 바로 조절한다.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.label,
    required this.skin,
    required this.onChanged,
  });

  final int value;
  final String label;
  final Skin skin;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label ${Strings.menuServings(value)}',
        child: Row(
          children: [
            _round(context, Icons.remove_rounded, value > 1,
                () => onChanged(value - 1)),
            SizedBox(
              width: 56,
              child: Text(
                Strings.menuServings(value),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            _round(context, Icons.add_rounded, value < 8,
                () => onChanged(value + 1)),
          ],
        ),
      );

  Widget _round(
          BuildContext context, IconData icon, bool on, VoidCallback onTap) =>
      SizedBox(
        width: Tokens.tap,
        height: Tokens.tap,
        child: IconButton(
          onPressed: on ? onTap : null,
          iconSize: 18,
          color: skin.ink,
          disabledColor: skin.inkDim,
          style: IconButton.styleFrom(backgroundColor: skin.chipNeutral),
          icon: Icon(icon),
        ),
      );
}
