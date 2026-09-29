import 'package:flutter/foundation.dart';

import '../../domain/model/change_record.dart';
import '../../domain/repository/repositories.dart';

/// 변경 기록 화면의 상태.
///
/// 수량 변경과 상태 변경을 한 타임라인에 섞어 받는다. 상태 변경은 잔량 칸이 비어 있어
/// **개봉과 이동이 수량을 바꾸지 않는다는 사실**이 화면에 드러난다.
///
/// 기록은 **하루 단위**로 본다. 오늘로 열고 달력에서 다른 날을 고른다 — 대화가 길어지면
/// 하나의 긴 목록에서 "어제 뭐라고 했더라" 를 찾을 수 없다.
///
/// IMPORTANT: 날짜를 앱에서 자르지 않는다. 가구의 시간대로 잘라야 밤 늦게 한 일이 다음
/// 날로 넘어가지 않으며, 그 시간대는 서버가 안다.
class HistoryViewModel extends ChangeNotifier {
  HistoryViewModel({required CommandRepository command}) : _command = command;

  final CommandRepository _command;

  bool _loading = false;
  Object? _error;
  List<ChangeRecord> _records = const [];

  /// 지금 보고 있는 날. 처음에는 오늘이다.
  DateTime _day = _todayOnly();

  /// 기록이 남은 날짜. 달력이 고를 수 있는 날이다.
  List<DateTime> _days = const [];

  bool _undoing = false;
  Object? _undoError;

  bool get loading => _loading;
  Object? get error => _error;

  /// 그 날의 기록. **오래된 것이 위**다 — 대화처럼 읽고 맨 아래가 가장 최근이다.
  List<ChangeRecord> get records => _records;

  DateTime get day => _day;

  /// 기록이 남은 날짜. 최근 것부터다.
  List<DateTime> get days => _days;

  /// 오늘을 보고 있는지. 머리말 문구가 달라진다.
  bool get isToday => _sameDay(_day, _todayOnly());

  /// 고른 날에 기록이 있는지. 없으면 화면이 그 사실을 말한다.
  bool get isEmpty => !_loading && _error == null && _records.isEmpty;

  /// 되돌리기가 실패한 이유. 한 번 보여주고 [clearUndoError] 로 지운다.
  ///
  /// 읽기 실패([error])와 구분한다 — 되돌리기가 실패해도 이미 읽은 목록은 그대로
  /// 맞는 값이다. 목록을 지우면 사용자가 무엇을 잃었는지 알 수 없다.
  Object? get undoError => _undoError;

  /// 되돌리는 중인지. 두 번 눌러 두 번 되돌리면 안 된다.
  bool get undoing => _undoing;

  /// 한 기록을 되돌린다.
  ///
  /// 되돌리기도 **하나의 명령**이라 새 이력이 쌓인다. 지우지 않는 것이 이 제품의 규칙이다
  /// — 무엇을 되돌렸는지도 남아야 잘못을 추적할 수 있다.
  Future<void> undo(ChangeRecord record) async {
    final token = record.commandId;
    if (token == null || _undoing) return;
    _undoing = true;
    _undoError = null;
    notifyListeners();
    try {
      await _command.undo(token);
      await load();
    } catch (error) {
      // 목록은 그대로 둔다. 성공으로 바꾸지도, 화면을 비우지도 않는다.
      _undoError = error;
    } finally {
      _undoing = false;
      notifyListeners();
    }
  }

  void clearUndoError() {
    if (_undoError == null) return;
    _undoError = null;
    notifyListeners();
  }

  /// 다른 날을 고른다.
  Future<void> selectDay(DateTime value) async {
    final next = DateTime(value.year, value.month, value.day);
    if (_sameDay(next, _day)) return;
    _day = next;
    await load();
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _records = await _command.history(limit: 200, on: _day);
      // 서버는 최근 순으로 준다. 화면은 대화라서 오래된 것이 위다.
      _records = _records.reversed.toList(growable: false);
      await _loadDays();
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 달력이 고를 수 있는 날. 실패해도 그 날의 기록은 이미 읽었으므로 막지 않는다.
  Future<void> _loadDays() async {
    try {
      _days = await _command.historyDays(limit: 120);
    } catch (error) {
      debugPrint('history days failed: $error');
    }
  }

  static DateTime _todayOnly() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
