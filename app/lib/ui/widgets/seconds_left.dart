/// 남은 초를 세어 내려가는 한 줄.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

/// 남은 초로 문구를 다시 만든다.
///
/// "4초 뒤 돌아가요"를 고정해 두면 3초가 지난 뒤에도 4초라고 말한다. 1초마다 줄여
/// **1에서 멈춘다** — 낭독이 길어져 화면이 더 머물 수 있고, 0초는 이미 끝났다는 뜻이다.
class SecondsLeft extends StatefulWidget {
  const SecondsLeft({required this.from, required this.builder, super.key});

  /// 세기 시작하는 초.
  final int from;

  final Widget Function(BuildContext context, int seconds) builder;

  @override
  State<SecondsLeft> createState() => _SecondsLeftState();
}

class _SecondsLeftState extends State<SecondsLeft> {
  static const _last = 1;

  late int _left = widget.from;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(SecondsLeft old) {
    super.didUpdateWidget(old);
    if (old.from == widget.from) return;
    _left = widget.from;
    _start();
  }

  void _start() {
    _tick?.cancel();
    if (_left <= _last) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _left -= 1);
      if (_left <= _last) timer.cancel();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _left);
}
