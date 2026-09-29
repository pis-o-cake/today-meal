/// 권한 안내 (UI-01).
///
/// 목업 `Permission.dc.html` 이다 — 왜 마이크가 필요한지, 무엇을 쓰는지, 언제만 듣는지.
///
/// **권한을 받기 전에 대기 표시를 하지 않는다.** 거부해도 조회는 되므로 "마이크 없이
/// 둘러보기" 를 항상 남긴다. 영구 거부는 OS 설정으로 보낸다 — 앱에서 다시 물어도 창이
/// 뜨지 않는다.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/design/band.dart';
import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/inventory.dart';
import '../widgets/glass.dart';
import '../widgets/mascot.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({required this.onDone, super.key});

  /// 권한을 받았든 건너뛰었든 다음 화면으로 넘긴다.
  ///
  /// 권한 결과로 갈 곳을 가르지 않는다 — 거부해도 조회는 되므로 홈으로 간다. 음성이
  /// 안 되는 사실은 홈의 호출 상태 칩이 말한다.
  final VoidCallback onDone;

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _asking = false;
  bool _permanentlyDenied = false;

  /// 안드로이드는 마이크 창 한 번, iOS 는 마이크와 음성 인식 두 번이다.
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<void> _ask() async {
    setState(() => _asking = true);
    try {
      final mic = await Permission.microphone.request();
      // iOS 는 음성 인식을 따로 묻는다. 안드로이드에는 이 권한이 없다.
      if (!_isAndroid) await Permission.speech.request();
      if (!mounted) return;
      if (mic.isPermanentlyDenied) {
        setState(() {
          _asking = false;
          _permanentlyDenied = true;
        });
        return;
      }
      widget.onDone();
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final palette = skin.hello;

    // Scaffold 가 Material 을 깔아 준다. 없으면 잉크 효과가 조상을 찾지 못해 터진다.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: skin.background(palette)),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        const Mascot(mood: MascotMood.listening, size: 168),
                        const SizedBox(height: 8),
                        Text(
                          Strings.permissionTitle,
                          textAlign: TextAlign.center,
                          style: Tokens.hero(29, height: 1.3),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          Strings.permissionSubtitle,
                          textAlign: TextAlign.center,
                          style: text.bodyLarge?.copyWith(
                            color: skin.inkFaint,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _Reasons(skin: skin, android: _isAndroid),
                        if (_permanentlyDenied) ...[
                          const SizedBox(height: 16),
                          _Denied(skin: skin),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
              _Actions(
                skin: skin,
                android: _isAndroid,
                asking: _asking,
                denied: _permanentlyDenied,
                onAsk: _ask,
                onSkip: widget.onDone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 필요한 권한 셋. 왜 필요한지를 함께 적는다.
class _Reasons extends StatelessWidget {
  const _Reasons({required this.skin, required this.android});

  final Skin skin;
  final bool android;

  @override
  Widget build(BuildContext context) {
    final rows = [
      (
        Icons.mic_none_rounded,
        Strings.permissionMic,
        Strings.permissionMicWhy,
        skin.hello,
      ),
      (
        Icons.graphic_eq_rounded,
        android ? Strings.permissionSpeechAndroid : Strings.permissionSpeechIos,
        android
            ? Strings.permissionSpeechAndroidWhy
            : Strings.permissionSpeechIosWhy,
        skin.hello,
      ),
      (
        Icons.phone_iphone_rounded,
        Strings.permissionForeground,
        Strings.permissionForegroundWhy,
        skin.neutral,
      ),
    ];

    return Semantics(
      label: Strings.permissionSectionLabel,
      child: GlassPanel(
        weight: GlassWeight.thick,
        padding: EdgeInsets.zero,
        shadow: [skin.shade(0.08, 28, 10)],
        child: Column(
          children: [
            for (final (index, row) in rows.indexed) ...[
              if (index > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Divider(height: 1, color: skin.hairline),
                ),
              _Row(
                icon: row.$1,
                title: row.$2,
                why: row.$3,
                tint: row.$4.accentSoft,
                ink: row.$4.accent,
                skin: skin,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.why,
    required this.tint,
    required this.ink,
    required this.skin,
  });

  final IconData icon;
  final String title;
  final String why;
  final Color tint;
  final Color ink;
  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(Tokens.radiusField),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 22, color: ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                const SizedBox(height: 3),
                Text(
                  why,
                  style: text.bodyMedium?.copyWith(
                    color: skin.inkFaint,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 영구 거부. 앱에서 다시 물을 수 없으므로 설정으로 보낸다.
class _Denied extends StatelessWidget {
  const _Denied({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final danger = skin.band(Freshness.urgent);
    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.all(16),
      shadow: [skin.shade(0.06, 18, 6)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: danger.accent),
              const SizedBox(width: 8),
              Text(
                Strings.permissionDeniedTitle,
                style: text.titleSmall?.copyWith(color: danger.accent),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            Strings.permissionDeniedHint,
            style: text.bodyMedium?.copyWith(color: skin.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.skin,
    required this.android,
    required this.asking,
    required this.denied,
    required this.onAsk,
    required this.onSkip,
  });

  final Skin skin;
  final bool android;
  final bool asking;
  final bool denied;
  final VoidCallback onAsk;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 56,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: skin.strong,
                shape: const StadiumBorder(),
                shadows: [skin.shade(0.22, 22, 10)],
              ),
              child: InkWell(
                // 권한을 묻는 동안 두 번 누르지 못하게 막는다.
                onTap: asking ? null : (denied ? openAppSettings : onAsk),
                customBorder: const StadiumBorder(),
                child: Center(
                  child: asking
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: skin.onStrong,
                          ),
                        )
                      : Text(
                          denied
                              ? Strings.permissionOpenSettings
                              : android
                              ? Strings.permissionAllowAndroid
                              : Strings.permissionAllowIos,
                          style: text.titleMedium?.copyWith(
                            color: skin.onStrong,
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            android
                ? Strings.permissionPromptAndroid
                : Strings.permissionPromptIos,
            textAlign: TextAlign.center,
            style: text.labelMedium?.copyWith(
              color: skin.inkFaint,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(
            height: Tokens.tap,
            child: TextButton(
              onPressed: onSkip,
              child: Text(
                Strings.permissionSkip,
                style: text.bodyLarge?.copyWith(
                  color: skin.inkMuted,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
