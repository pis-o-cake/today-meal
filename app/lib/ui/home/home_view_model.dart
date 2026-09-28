import 'package:flutter/foundation.dart';

import '../../domain/model/inventory.dart';
import '../../domain/model/menu.dart';
import '../../domain/repository/repositories.dart';

/// 홈 화면의 상태를 만든다.
///
/// 화면은 이 값 하나를 받아 그린다. **신선도 등급은 서버가 판정한 값을 그대로 쓰고**
/// 여기서는 그 등급으로 묶기만 한다 — 묶는 것은 표현이고 판정은 사실이다.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required InventoryRepository inventory,
    required MenuRepository menu,
  })  : _inventory = inventory,
        _menu = menu;

  final InventoryRepository _inventory;
  final MenuRepository _menu;

  bool _loading = false;
  Object? _error;
  FridgeCondition _condition = const FridgeCondition.empty();
  List<IngredientBatch> _batches = const [];
  List<MenuSuggestion> _menus = const [];

  bool get loading => _loading;
  Object? get error => _error;
  FridgeCondition get condition => _condition;
  List<MenuSuggestion> get menus => _menus;

  /// 신선도 밴드. 화면이 세로로 쌓는 순서 그대로다.
  ///
  /// 빈 밴드는 내보내지 않는다 — 비어 있는 칸을 보여주면 무엇이 문제인지 흐려진다.
  List<FreshnessBand> get bands {
    const order = [
      Freshness.expired,
      Freshness.urgent,
      Freshness.soon,
      Freshness.fresh,
      Freshness.unknown,
    ];
    return [
      for (final grade in order)
        if (_batches.any((b) => b.freshness == grade))
          FreshnessBand(
            grade: grade,
            batches: _batches.where((b) => b.freshness == grade).toList(growable: false),
          ),
    ];
  }

  /// 재고와 컨디션, 추천을 함께 읽는다.
  Future<void> load({bool withMenus = true}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _inventory.listBatches(),
        _inventory.condition(),
      ]);
      _batches = results[0] as List<IngredientBatch>;
      _condition = results[1] as FridgeCondition;
      // 추천은 모델 호출이라 느리고 실패할 수 있다. 재고 표시를 막지 않는다.
      if (withMenus) await _loadMenus();
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadMenus() async {
    try {
      _menus = await _menu.createSuggestions(servings: null);
    } catch (error) {
      // 추천 실패를 전체 실패로 만들지 않는다. 재고는 이미 읽었다.
      _menus = const [];
      debugPrint('menu suggestion failed: $error');
    }
  }
}

/// 같은 신선도 등급의 재료 묶음.
class FreshnessBand {
  const FreshnessBand({required this.grade, required this.batches});

  final Freshness grade;
  final List<IngredientBatch> batches;

  int get count => batches.length;

  /// 이 밴드의 재료로 만들 메뉴를 권할 수 있는지. 기한이 지난 것은 권하지 않는다.
  bool get suggestsCooking => grade.isCookable && grade != Freshness.unknown;
}
