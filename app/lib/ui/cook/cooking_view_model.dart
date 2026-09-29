/// 조리 진행의 상태.
///
/// 단계 위치와 타이머를 갖는다. 타이머는 **단계에 시간이 적혀 있을 때만** 돌고, 없는 단계에서
/// 임의의 시간으로 돌지 않는다 — 그러면 조리 중에 엉뚱하게 울린다.
///
/// WARNING: 화면이 떠 있는 동안만 돈다. 배경에서 도는 알림 타이머가 아니다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/model/menu.dart';
import '../../domain/repository/repositories.dart';
import 'cook_session.dart';

class CookingViewModel extends ChangeNotifier {
  CookingViewModel({required CookPlan plan, required MenuRepository menu})
      : _plan = plan,
        _menu = menu {
    _armTimer();
  }

  final CookPlan _plan;
  final MenuRepository _menu;

  int _at = 0;
  int? _remaining;
  bool _running = false;
  Timer? _ticker;

  bool _finishing = false;
  CookedResult? _result;
  Object? _finishError;

  CookPlan get plan => _plan;

  /// 지금 단계의 번호(0부터).
  int get at => _at;

  /// 지금 단계.
  CookStep get step => _plan.steps[_at];

  bool get isFirst => _at == 0;
  bool get isLast => _at >= _plan.total - 1;

  /// 다음 단계의 글줄. 마지막이면 `null`.
  String? get nextText => isLast ? null : _plan.steps[_at + 1].text;

  /// 이 단계에 타이머가 있는지.
  bool get hasTimer => step.hasTimer;

  /// 남은 초. 타이머가 없으면 `null`.
  int? get remaining => _remaining;

  /// 타이머가 도는 중인지. 멈춤 상태와 구분한다.
  bool get running => _running;

  /// 타이머가 끝났는지. 다음 단계로 넘어갈 때임을 화면이 강조한다.
  bool get rang => hasTimer && _remaining == 0;

  /// 남은 시간의 비율(0~1). 눈금을 그리는 값이다.
  double get progress {
    final total = step.timerSeconds;
    if (total == null || total == 0) return 0;
    return ((_remaining ?? total) / total).clamp(0.0, 1.0);
  }

  bool get finishing => _finishing;

  /// 조리 확인 결과. 서버가 재고를 뺀 내용이 담긴다.
  CookedResult? get result => _result;

  Object? get finishError => _finishError;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void next() {
    if (isLast) return;
    _moveTo(_at + 1);
  }

  void previous() {
    if (isFirst) return;
    _moveTo(_at - 1);
  }

  void goTo(int index) {
    if (index < 0 || index >= _plan.total || index == _at) return;
    _moveTo(index);
  }

  /// 타이머를 시작하거나 멈춘다. 타이머가 없는 단계에서는 아무 일도 하지 않는다.
  void toggleTimer() {
    if (!hasTimer) return;
    if (_running) {
      _stopTicker();
      _running = false;
      notifyListeners();
      return;
    }
    // 다 울린 타이머를 다시 누르면 처음부터 돈다.
    if (_remaining == null || _remaining == 0) _remaining = step.timerSeconds;
    _startTicker();
  }

  /// 1분을 더한다. 조리 중에 가장 자주 하는 조정이다.
  void addMinute() {
    if (!hasTimer) return;
    _remaining = (_remaining ?? step.timerSeconds ?? 0) + 60;
    notifyListeners();
  }

  /// 이 단계의 타이머를 처음부터.
  void restartTimer() {
    if (!hasTimer) return;
    _remaining = step.timerSeconds;
    _startTicker();
  }

  /// 조리를 마친다.
  ///
  /// 추천에서 온 조리만 서버에 알린다([CookPlan.canDeduct]). 영상 레시피는 차감 단위가
  /// 없으므로 **뺐다고 말하지 않는다** — 화면이 말로 빼라고 안내한다.
  Future<void> finish() async {
    _stopTicker();
    if (_finishing) return;
    final suggestionId = _plan.suggestionId;
    if (suggestionId == null) return;

    _finishing = true;
    _finishError = null;
    notifyListeners();
    try {
      _result = await _menu.markCooked(suggestionId);
    } catch (error) {
      _finishError = error;
      debugPrint('mark cooked failed: $error');
    } finally {
      _finishing = false;
      notifyListeners();
    }
  }

  void _moveTo(int index) {
    _stopTicker();
    _at = index;
    _armTimer();
    notifyListeners();
  }

  /// 새 단계의 타이머를 걸어 둔다. **저절로 시작하지 않는다.**
  ///
  /// 단계를 읽기 전에 시간이 흐르기 시작하면 사용자가 손을 놓친다. 시작은 사용자가 누르거나
  /// "타이머 시작" 이라고 말할 때다.
  void _armTimer() {
    _running = false;
    _remaining = _plan.steps[_at].timerSeconds;
  }

  void _startTicker() {
    _stopTicker();
    _running = true;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = (_remaining ?? 0) - 1;
      _remaining = left <= 0 ? 0 : left;
      if (_remaining == 0) {
        _stopTicker();
        _running = false;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }
}
