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

  bool get loading => _loading;
  Object? get error => _error;
  List<ChangeRecord> get records => _records;

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
