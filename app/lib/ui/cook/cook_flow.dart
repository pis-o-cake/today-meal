/// 조리 한 판의 화면 흐름 (UI-10 → UI-11).
///
/// 진행과 완료를 **한 route 안에서** 바꾼다. 둘을 각각 route 로 두면 [CookingViewModel]
/// 의 주인이 없어진다 — 셸이 닫으면 닫히는 애니메이션 중에 완료 화면이 이미 닫힌
/// ViewModel 을 다시 그리고, `A CookingViewModel was used after being disposed` 로 터진다.
///
/// 한 route 가 소유하면 화면이 완전히 사라질 때 ViewModel 도 함께 닫힌다.
/// 뒤로 가기로 끝난 조리에 돌아가지 않는 것도 그대로다 — 완료로 넘어간 뒤에는 진행
/// 화면을 스택에 남기지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'cook_done_screen.dart';
import 'cook_session.dart';
import 'cooking_screen.dart';
import 'cooking_view_model.dart';

class CookFlow extends StatefulWidget {
  const CookFlow({required this.plan, super.key});

  final CookPlan plan;

  @override
  State<CookFlow> createState() => _CookFlowState();
}

class _CookFlowState extends State<CookFlow> {
  /// 조리를 시작한 시각. 완료 화면이 걸린 시간을 적는다.
  final _started = DateTime.now();

  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final cooking = context.watch<CookingViewModel>();
    if (!_done) {
      return CookingScreen(onDone: () => _finish(cooking));
    }
    return CookDoneScreen(
      plan: widget.plan,
      result: cooking.result,
      error: cooking.finishError,
      minutes: _elapsed(),
      undoing: cooking.undoing,
      undone: cooking.undone,
      undoError: cooking.undoError,
      onUndo: cooking.canUndo ? cooking.undoCooked : null,
      onClose: () => Navigator.of(context).pop(),
    );
  }

  /// 서버 확인이 끝난 뒤에 넘어간다. 먼저 넘기면 "뺐어요" 를 확인 전에 보인다.
  Future<void> _finish(CookingViewModel cooking) async {
    await cooking.finish();
    if (!mounted) return;
    setState(() => _done = true);
  }

  /// 조리에 걸린 시간(분). 1분 미만도 1분으로 적는다 — 0분 걸렸다고 쓸 수는 없다.
  int _elapsed() {
    final minutes = DateTime.now().difference(_started).inMinutes;
    return minutes < 1 ? 1 : minutes;
  }
}
