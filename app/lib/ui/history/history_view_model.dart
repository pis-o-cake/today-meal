import 'package:flutter/foundation.dart';

import '../../domain/model/change_record.dart';
import '../../domain/repository/repositories.dart';

/// 변경 기록 화면의 상태.
///
/// 수량 변경과 상태 변경을 한 타임라인에 섞어 받는다. 상태 변경은 잔량 칸이 비어 있어
/// **개봉과 이동이 수량을 바꾸지 않는다는 사실**이 화면에 드러난다.
///
/// 기록은 **전체를 최근순으로** 받는다. 날짜로 자르지 않는다 — 되돌릴 수 있는 것은 전체에서
/// 가장 최근의 변경이고, 날짜를 골라 보면 그 날의 마지막 줄을 최신으로 착각하게 된다.
///
/// 화면은 대화처럼 쌓아 아래가 가장 최근이며, 열 때 그 끝을 보여준다.
class HistoryViewModel extends ChangeNotifier {
  HistoryViewModel({required CommandRepository command}) : _command = command;

  final CommandRepository _command;

  bool _loading = false;
  Object? _error;
  List<ChangeRecord> _records = const [];

  bool _undoing = false;
  Object? _undoError;

  bool get loading => _loading;
  Object? get error => _error;

  /// 전체 기록. **오래된 것이 위**다 — 대화처럼 읽고 맨 아래가 가장 최근이다.
  List<ChangeRecord> get records => _records;

  /// 기록이 하나도 없는지. 없으면 화면이 그 사실을 말한다.
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

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      // 날짜로 자르지 않는다. 되돌릴 수 있는 것은 **전체에서 가장 최근**의 변경이다.
      _records = await _command.history(limit: _limit);
      // 서버는 최근 순으로 준다. 화면은 대화라서 오래된 것이 위다.
      _records = _records.reversed.toList(growable: false);
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 한 번에 읽는 줄 수. 서버가 허용하는 최대다.
  static const _limit = 200;
}
