import 'package:flutter/foundation.dart';

import '../../domain/model/change_record.dart';
import '../../domain/repository/repositories.dart';

/// 변경 기록 화면의 상태.
///
/// 수량 변경과 상태 변경을 한 타임라인에 섞어 받는다. 상태 변경은 잔량 칸이 비어 있어
/// **개봉과 이동이 수량을 바꾸지 않는다는 사실**이 화면에 드러난다.
class HistoryViewModel extends ChangeNotifier {
  HistoryViewModel({required CommandRepository command}) : _command = command;

  final CommandRepository _command;

  bool _loading = false;
  Object? _error;
  List<ChangeRecord> _records = const [];

  bool _undoing = false;

  bool get loading => _loading;
  Object? get error => _error;
  List<ChangeRecord> get records => _records;

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
    notifyListeners();
    try {
      await _command.undo(token);
      await load();
    } catch (error) {
      _error = error;
    } finally {
      _undoing = false;
      notifyListeners();
    }
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _records = await _command.history(limit: 100);
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
