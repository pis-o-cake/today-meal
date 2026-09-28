import 'package:flutter/foundation.dart';

import '../../core/design/band.dart';
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

  Freshness? _selected;

  bool get loading => _loading;
  Object? get error => _error;
  FridgeCondition get condition => _condition;
  List<MenuSuggestion> get menus => _menus;

  /// 등급별 재료 종 수. **빈 등급도 0 으로 넣는다.**
  ///
  /// 아치는 등급 5칸을 항상 같은 자리에 두므로 빈 칸을 빼면 위치가 흔들린다. 목록으로
  /// 쌓는 [bands] 와 규칙이 다른 이유다.
  Map<Freshness, int> get counts => {
        for (final grade in Bands.ordered)
          grade: _batches.where((b) => b.freshness == grade).length,
      };

  /// 지금 고른 등급. 고르지 않았으면 가장 급한 등급이 잡힌다.
  Freshness get selected => _selected ?? _mostUrgent();

  /// 고른 등급의 재료.
  List<IngredientBatch> get selectedBatches => batchesOf(selected);

  /// 한 등급의 재료.
  ///
  /// 아치를 끄는 동안 화면은 아직 고르지 않은 등급을 미리 보여준다. 그때도 캐릭터와
  /// 칩이 **같은 등급**을 가리켜야 한다.
  List<IngredientBatch> batchesOf(Freshness grade) =>
      _batches.where((b) => b.freshness == grade).toList(growable: false);

  /// 고른 등급에서 권할 메뉴.
  ///
  /// **그 등급의 재료를 실제로 쓰는 메뉴만** 권한다. 서버 추천은 냉장고 전체를 보고
  /// 만들어지므로, 그냥 첫 번째를 꺼내면 재료가 하나도 없는 등급에서도 메뉴가 뜬다.
  /// 실기기에서 "챙길 것 0가지" 옆에 메뉴가 떠 있었다.
  ///
  /// 기한이 지난 등급과 기한을 모르는 등급에서는 권하지 않는다 — 먼저 할 일이 다르다.
  MenuSuggestion? get topMenu => menusFor(selected).firstOrNull;

  /// 첫 메뉴 말고 남은 개수.
  int get otherMenuCount {
    final count = menusFor(selected).length;
    return count <= 1 ? 0 : count - 1;
  }

  /// 한 등급에서 권할 메뉴.
  List<MenuSuggestion> menusFor(Freshness grade) {
    if (!grade.isCookable || grade == Freshness.unknown) return const [];
    final names = batchesOf(grade).map((b) => b.name).toSet();
    if (names.isEmpty) return const [];
    return [
      for (final menu in _menus)
        if (menu.priorityIngredients.any(names.contains)) menu,
    ];
  }

  /// 등급을 고른다. 화면 배색이 함께 바뀐다.
  void select(Freshness grade) {
    if (_selected == grade) return;
    _selected = grade;
    notifyListeners();
  }

  /// 재료가 있는 등급 중 가장 급한 것. 하나도 없으면 여유로 둔다.
  Freshness _mostUrgent() {
    const priority = [
      Freshness.urgent,
      Freshness.expired,
      Freshness.soon,
      Freshness.unknown,
      Freshness.fresh,
    ];
    for (final grade in priority) {
      if (_batches.any((b) => b.freshness == grade)) return grade;
    }
    return Freshness.fresh;
  }

  /// 신선도 밴드. 화면이 세로로 쌓는 순서 그대로다.
  ///
  /// 빈 밴드는 내보내지 않는다 — 비어 있는 칸을 보여주면 무엇이 문제인지 흐려진다.
  List<FreshnessBand> get bands {
    return [
      for (final grade in Bands.ordered)
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
