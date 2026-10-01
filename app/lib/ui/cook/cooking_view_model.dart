/// 조리 진행의 상태.
///
/// 단계 위치와 타이머를 갖는다. 타이머는 **단계에 시간이 적혀 있을 때만** 돌고, 없는 단계에서
/// 임의의 시간으로 돌지 않는다 — 그러면 조리 중에 엉뚱하게 울린다.
///
/// WARNING: 화면이 떠 있는 동안만 돈다. 배경에서 도는 알림 타이머가 아니다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/l10n/strings.dart';
import '../../core/voice/voice_ports.dart';
import '../../domain/model/menu.dart';
import '../../domain/repository/repositories.dart';
import 'cook_command.dart';
import 'cook_session.dart';

class CookingViewModel extends ChangeNotifier {
  CookingViewModel({
    required CookPlan plan,
    required MenuRepository menu,
    required CommandRepository command,
    Future<bool> Function(String text)? narrate,
    Future<void> Function()? hush,
    Stream<Heard>? heard,
  })  : _plan = plan,
        _menu = menu,
        _command = command,
        _narrate = narrate,
        _hush = hush {
    _armTimer();
    _hearing = heard?.listen(_obey);
    unawaited(_readStep());
  }

  final CookPlan _plan;
  final MenuRepository _menu;
  final CommandRepository _command;

  /// 단계를 읽어주는 수단. 없으면 읽지 않는다.
  final Future<bool> Function(String text)? _narrate;

  /// 읽던 것을 멈추는 수단.
  final Future<void> Function()? _hush;

  /// 호출어 없이 들은 말. 조리 중에만 듣는다.
  StreamSubscription<Heard>? _hearing;

  /// 마지막으로 따른 말. 한 번 말한 것이 여러 번 와도 한 번만 따른다.
  int? _obeyedSegment;
  String? _obeyedKey;

  /// 사용자가 말로 건 타이머의 길이(초). 단계가 바뀌면 지운다.
  int? _asked;

  bool _reading = false;

  /// 읽기 시작한 횟수. 밀려난 낭독이 끝나면서 표시를 끄지 않게 한다.
  int _reads = 0;
  bool _closed = false;

  int _at = 0;
  int? _remaining;
  bool _running = false;
  Timer? _ticker;

  bool _finishing = false;
  CookedResult? _result;
  Object? _finishError;

  bool _undoing = false;
  bool _undone = false;
  Object? _undoError;

  CookPlan get plan => _plan;

  /// 지금 단계를 읽어주는 중인지. **실제로 읽는 동안만** 참이다.
  bool get reading => _reading;

  /// 지금 단계의 번호(0부터).
  int get at => _at;

  /// 지금 단계.
  CookStep get step => _plan.steps[_at];

  bool get isFirst => _at == 0;
  bool get isLast => _at >= _plan.total - 1;

  /// 다음 단계의 글줄. 마지막이면 `null`.
  String? get nextText => isLast ? null : _plan.steps[_at + 1].text;

  /// 이 단계에 타이머가 있는지. 원본에 적힌 시간이거나 사용자가 말로 건 시간이다.
  bool get hasTimer => _total != null;

  /// 타이머의 전체 길이(초). 말로 건 시간이 원본에 적힌 시간보다 앞선다.
  int? get _total => _asked ?? step.timerSeconds;

  /// 남은 초. 타이머가 없으면 `null`.
  int? get remaining => _remaining;

  /// 타이머가 도는 중인지. 멈춤 상태와 구분한다.
  bool get running => _running;

  /// 타이머가 끝났는지. 다음 단계로 넘어갈 때임을 화면이 강조한다.
  bool get rang => hasTimer && _remaining == 0;

  /// 남은 시간의 비율(0~1). 눈금을 그리는 값이다.
  double get progress {
    final total = _total;
    if (total == null || total == 0) return 0;
    return ((_remaining ?? total) / total).clamp(0.0, 1.0);
  }

  bool get finishing => _finishing;

  /// 조리 확인 결과. 서버가 재고를 뺀 내용이 담긴다.
  CookedResult? get result => _result;

  Object? get finishError => _finishError;

  /// 되돌리는 중인지. 두 번 눌러 두 번 되돌리면 안 된다.
  bool get undoing => _undoing;

  /// 되돌렸는지. 화면이 "뺐어요" 를 거두고 되돌린 사실을 말한다.
  bool get undone => _undone;

  /// 되돌리기가 실패한 이유. 실패를 성공처럼 그리지 않는다.
  Object? get undoError => _undoError;

  /// 되돌릴 수 있는지.
  ///
  /// 서버가 실제로 뺐고([CookedResult.undoToken]) 아직 되돌리지 않았을 때만이다.
  /// 영상 조리나 되물음으로 아무것도 빼지 않았으면 되돌릴 것이 없다.
  bool get canUndo =>
      !_undone && !_undoing && (_result?.undoToken?.isNotEmpty ?? false);

  @override
  void dispose() {
    _closed = true;
    _ticker?.cancel();
    unawaited(_hearing?.cancel());
    unawaited(_hush?.call());
    super.dispose();
  }

  /// 지금 단계를 다시 읽는다.
  void readAgain() => unawaited(_readStep());

  /// 말한 길이로 타이머를 걸고 바로 돌린다.
  ///
  /// 단계에 시간이 적혀 있지 않아도 된다. 앱이 시간을 만드는 것이 아니라 **사용자가
  /// 말한 시간**이다.
  void setTimer(Duration length) {
    if (length <= Duration.zero) return;
    _asked = length.inSeconds;
    _remaining = _asked;
    _startTicker();
  }

  /// 호출어 없이 들은 말을 따른다.
  ///
  /// 한 번 말한 것이 중간 결과와 후보로 여러 번 온다. 같은 말을 두 번 따르면 "다음" 한
  /// 마디에 두 단계가 넘어간다. 타이머 길이만은 말이 길어지며 바뀔 수 있어 다시 받는다.
  void _obey(Heard heard) {
    if (_closed || _finishing) return;
    final command = readCookCommand(heard.transcript);
    if (command == null) return;
    if (heard.segment == _obeyedSegment &&
        (command is! CookTimerSet || command.key == _obeyedKey)) {
      return;
    }
    _obeyedSegment = heard.segment;
    _obeyedKey = command.key;

    switch (command) {
      case CookNext():
        next();
      case CookPrevious():
        previous();
      case CookReadAgain():
        readAgain();
      case CookTimerStart():
        if (!_running) toggleTimer();
      case CookTimerStop():
        if (_running) toggleTimer();
      case CookTimerSet(:final length):
        setTimer(length);
        // 손이 바빠 화면을 못 본다. 걸렸다는 것을 말로 알린다.
        unawaited(_say(Strings.cookingTimerStarted(length.inSeconds)));
    }
  }

  /// 지금 단계를 읽는다. 읽는 중에 단계가 바뀌면 앞의 낭독은 밀려난다.
  Future<void> _readStep() => _say(step.text);

  Future<void> _say(String line) async {
    final narrate = _narrate;
    if (narrate == null || _closed) return;
    final mine = ++_reads;
    _reading = true;
    notifyListeners();
    try {
      await narrate(line);
    } finally {
      if (mine == _reads && !_closed) {
        _reading = false;
        notifyListeners();
      }
    }
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
    if (_remaining == null || _remaining == 0) _remaining = _total;
    _startTicker();
  }

  /// 1분을 더한다. 조리 중에 가장 자주 하는 조정이다.
  void addMinute() {
    if (!hasTimer) return;
    _remaining = (_remaining ?? _total ?? 0) + 60;
    notifyListeners();
  }

  /// 이 단계의 타이머를 처음부터.
  void restartTimer() {
    if (!hasTimer) return;
    _remaining = _total;
    _startTicker();
  }

  /// 조리를 마친다.
  ///
  /// 추천에서 온 조리만 서버에 알린다([CookPlan.canDeduct]). 영상 레시피는 차감 단위가
  /// 없으므로 **뺐다고 말하지 않는다** — 화면이 말로 빼라고 안내한다.
  ///
  /// IMPORTANT: 화면에서 조리한 인분([CookPlan.servings])을 함께 보낸다. 서버에 저장된
  /// 인분으로 빼면 4인분을 만든 사람에게 2인분이 빠진다.
  Future<void> finish() async {
    _stopTicker();
    // 끝낸 뒤에도 마지막 단계를 계속 읽으면 완료 화면의 안내를 가린다.
    _reads += 1;
    _reading = false;
    unawaited(_hush?.call());
    if (_finishing) return;
    final suggestionId = _plan.suggestionId;
    if (suggestionId == null) return;

    _finishing = true;
    _finishError = null;
    notifyListeners();
    try {
      _result = await _menu.markCooked(suggestionId, servings: _plan.servings);
    } catch (error) {
      _finishError = error;
      debugPrint('mark cooked failed: $error');
    } finally {
      _finishing = false;
      notifyListeners();
    }
  }

  /// 방금 한 차감을 되돌린다.
  ///
  /// IMPORTANT: 화면만 닫는 것과 다르다. 서버의 그 명령을 실제로 역산해야 냉장고가
  /// 조리 전으로 돌아간다 — 버튼이 닫기만 하면 사용자는 되돌렸다고 믿고 틀린 재고를 본다.
  Future<void> undoCooked() async {
    final token = _result?.undoToken;
    if (token == null || token.isEmpty || _undoing || _undone) return;

    _undoing = true;
    _undoError = null;
    notifyListeners();
    try {
      await _command.undo(token);
      _undone = true;
    } catch (error) {
      _undoError = error;
      debugPrint('undo cooked failed: $error');
    } finally {
      _undoing = false;
      notifyListeners();
    }
  }

  void _moveTo(int index) {
    _stopTicker();
    _at = index;
    _armTimer();
    notifyListeners();
    unawaited(_readStep());
  }

  /// 새 단계의 타이머를 걸어 둔다. **저절로 시작하지 않는다.**
  ///
  /// 단계를 읽기 전에 시간이 흐르기 시작하면 사용자가 손을 놓친다. 시작은 사용자가 누르거나
  /// "타이머 시작" 이라고 말할 때다.
  void _armTimer() {
    _running = false;
    // 말로 건 타이머는 그 단계의 것이다. 다음 단계로 가져가지 않는다.
    _asked = null;
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
