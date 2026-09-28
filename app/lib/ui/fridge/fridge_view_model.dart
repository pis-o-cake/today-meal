import 'package:flutter/foundation.dart';

import '../../domain/model/inventory.dart';
import '../../domain/repository/repositories.dart';

/// 냉장고 화면의 상태.
///
/// 검색과 보관 위치 필터는 화면 표현이므로 여기서 한다. 잔량과 기한 판정은 서버가 한 값을
/// 그대로 쓴다.
class FridgeViewModel extends ChangeNotifier {
  FridgeViewModel({required InventoryRepository inventory}) : _inventory = inventory;

  final InventoryRepository _inventory;

  bool _loading = false;
  Object? _error;
  List<IngredientBatch> _all = const [];
  String _query = '';
  StorageLocation? _storage;

  bool get loading => _loading;
  Object? get error => _error;
  String get query => _query;
  StorageLocation? get storage => _storage;
  int get totalCount => _all.length;

  /// 검색과 필터를 적용한 목록.
  List<IngredientBatch> get visible {
    final needle = _query.trim();
    return _all.where((batch) {
      if (_storage != null && batch.storage != _storage) return false;
      if (needle.isEmpty) return true;
      return batch.name.contains(needle);
    }).toList(growable: false);
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _all = await _inventory.listBatches();
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void search(String value) {
    _query = value;
    notifyListeners();
  }

  void filterStorage(StorageLocation? value) {
    _storage = value;
    notifyListeners();
  }
}
