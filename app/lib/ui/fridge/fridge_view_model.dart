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
  Freshness? _grade;

  bool get loading => _loading;
  Object? get error => _error;
  String get query => _query;
  StorageLocation? get storage => _storage;

  /// 고른 기한 상태. `null` 이면 전체다.
  Freshness? get grade => _grade;
  int get totalCount => _all.length;

  /// 검색과 필터를 적용한 목록.
  List<IngredientBatch> get visible {
    final needle = _query.trim();
    return _all.where((batch) {
      if (_storage != null && batch.storage != _storage) return false;
      if (_grade != null && batch.freshness != _grade) return false;
      if (needle.isEmpty) return true;
      return batch.name.contains(needle);
    }).toList(growable: false);
  }

  /// 신선도 등급으로 묶은 목록. **급한 것부터** 위에 온다.
  ///
  /// 빈 등급은 내보내지 않는다 — 목록에서는 자리를 지킬 이유가 없고, 비어 있는 칸이
  /// 무엇이 문제인지 흐린다. 자리가 고정인 것은 오늘 화면의 아치뿐이다.
  List<FridgeSection> get sections {
    const order = [
      Freshness.expired,
      Freshness.urgent,
      Freshness.soon,
      Freshness.unknown,
      Freshness.fresh,
    ];
    final shown = visible;
    return [
      for (final grade in order)
        if (shown.any((b) => b.freshness == grade))
          FridgeSection(
            grade: grade,
            batches: shown.where((b) => b.freshness == grade).toList(growable: false),
          ),
    ];
  }

  /// 한 등급의 개수. 필터를 무시하고 냉장고 전체를 센다 — 머리말의 요약은 지금 보고
  /// 있는 칸이 아니라 냉장고 전체를 말해야 한다.
  int countOf(Freshness grade) =>
      _all.where((b) => b.freshness == grade).length;

  /// 한 보관 위치의 개수.
  int countOfStorage(StorageLocation value) =>
      _all.where((b) => b.storage == value).length;

  /// 상태 칩에 붙일 개수.
  ///
  /// **보관 위치 필터는 반영하고 기한 상태 필터는 무시한다.** 칩의 수는 "그 칩을 누르면 몇
  /// 개가 남는가" 여야 하며, 자기 자신으로 걸러진 수를 보여주면 다른 칩이 모두 0 이 된다.
  int countInScope(Freshness? value) {
    final scoped = _all.where((batch) =>
        _storage == null || batch.storage == _storage);
    if (value == null) return scoped.length;
    return scoped.where((batch) => batch.freshness == value).length;
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

  /// 기한 상태를 고른다. 이미 고른 것을 다시 누르면 전체로 돌아간다.
  void filterGrade(Freshness? value) {
    final next = _grade == value ? null : value;
    if (_grade == next) return;
    _grade = next;
    notifyListeners();
  }
}

/// 같은 등급의 재료 묶음.
class FridgeSection {
  const FridgeSection({required this.grade, required this.batches});

  final Freshness grade;
  final List<IngredientBatch> batches;
}
