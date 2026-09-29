/// 스플래시 (UI-00).
///
/// 목업 `Splash.dc.html` 이다 — 냉장고가 위에서 **착지하고**, 문이 열리고, 웃고, 제목이
/// 떠오른다.
///
/// 목업의 4.2초 반복은 관찰용이다. 앱은 [Motion.splash] 동안 **한 번만** 재생하고 준비가
/// 끝나면 다음 화면으로 넘어간다.
///
/// IMPORTANT: 초기화 실패를 애니메이션 반복으로 감추지 않는다. 준비가 끝나지 않으면
/// 재시도를 안내한다 — 도는 그림은 "살아 있다" 는 뜻이라 사용자가 계속 기다리게 된다.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design/band.dart';
import '../../core/design/motion.dart';
import '../../core/design/skin.dart';
import '../../core/l10n/strings.dart';
import '../widgets/mascot.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({required this.onReady, this.prepare, super.key});

  /// 연출이 끝나고 준비도 끝났을 때 부른다.
  final VoidCallback onReady;

  /// 준비 작업. 연출과 **동시에** 돌린다. 없으면 연출 시간만 기다린다.
  final Future<void> Function()? prepare;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _play = AnimationController(
    vsync: this,
    duration: Motion.splash,
  );

  Object? _error;
  bool _started = false;

  // IMPORTANT: `initState` 에서 시작하지 않는다. 연출은 모션 감소 설정(MediaQuery)을
  // 읽는데, `initState` 안에서 읽으면 의존성이 아직 붙지 않아 예외가 난다.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    // 연출과 준비를 함께 돌린다. 준비가 빨라도 연출은 끝까지 보여준다.
    final show = context.reduceMotion
        ? Future<void>.delayed(const Duration(milliseconds: 400))
        : _play.forward().orCancel.catchError((_) {});
    try {
      await Future.wait([show, widget.prepare?.call() ?? Future<void>.value()]);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
      return;
    }
    if (!mounted) return;
    widget.onReady();
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final palette = skin.hello;

    // Scaffold 가 Material 을 깔아 준다. 재시도 버튼이 조상을 찾아야 한다.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: skin.background(palette, focusY: -0.2),
        ),
        child: Semantics(
          label: Strings.splashLabel,
          child: Center(
            child: AnimatedBuilder(
              animation: _play,
              builder: (context, _) => _stage(text, skin, palette),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stage(TextTheme text, Skin skin, BandPalette palette) {
    // 착지는 앞 26% 에서 끝난다. 목업의 keyTimes 를 세 구간으로 줄인 것이다.
    final drop = Curves.easeOutBack.transform(
      (_play.value / 0.26).clamp(0.0, 1.0),
    );
    final titleIn = ((_play.value - 0.22) / 0.18).clamp(0.0, 1.0);
    final tagIn = ((_play.value - 0.34) / 0.18).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          offset: Offset(0, -110 * (1 - drop)),
          child: const Mascot(mood: MascotMood.hello, size: 200),
        ),
        const SizedBox(height: 18),
        Opacity(
          opacity: titleIn,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - titleIn)),
            child: Text(
              Strings.appName,
              style: text.headlineMedium?.copyWith(fontSize: 34),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Opacity(
          opacity: tagIn,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - tagIn)),
            child: Text(
              Strings.appTagline,
              style: text.bodyLarge?.copyWith(
                fontSize: 16,
                color: skin.inkFaint,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(height: 40),
        // 실패하면 점을 굴리지 않고 무엇이 잘못됐는지 말한다.
        SizedBox(
          height: 48,
          child: _error == null
              ? _Dots(play: _play, color: palette.accentBright)
              : _Retry(skin: skin, onRetry: _retry),
        ),
      ],
    );
  }

  void _retry() {
    setState(() => _error = null);
    _play.reset();
    unawaited(_run());
  }
}

/// 준비 중 점 셋. 차례로 튀어 오른다.
class _Dots extends StatelessWidget {
  const _Dots({required this.play, required this.color});

  final AnimationController play;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final still = context.reduceMotion;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Transform.translate(
              offset: Offset(0, still ? 0 : -9 * _hop(play.value, i)),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.85 - i * 0.25),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 점 하나의 튀어 오름. 점마다 위상을 어긋나게 한다.
  double _hop(double t, int index) {
    final phase = ((t * 3 - index * 0.15) % 1).clamp(0.0, 1.0);
    if (phase > 0.4) return 0;
    final up = phase / 0.4;
    return up < 0.5 ? up * 2 : (1 - up) * 2;
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.skin, required this.onRetry});

  final Skin skin;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        Strings.splashFailed,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: skin.inkFaint),
      ),
      const SizedBox(height: 4),
      TextButton(onPressed: onRetry, child: const Text(Strings.retry)),
    ],
  );
}
