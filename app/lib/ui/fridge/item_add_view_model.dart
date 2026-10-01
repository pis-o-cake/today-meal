/// 재료 넣기의 입력 상태.
///
/// 목업 밖의 화면이다. 말로 넣기 어려운 때(시끄럽거나, 이름이 낯설거나)를 위한 길이며, 서버는
/// 말로 넣을 때와 같은 기록을 남긴다.
///
/// IMPORTANT: 넣기에 성공하지 않으면 **넣은 것처럼 닫지 않는다.**
library;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../domain/model/inventory.dart';
import '../../domain/repository/repositories.dart';

class ItemAddViewModel extends ChangeNotifier {
  ItemAddViewModel({required InventoryRepository inventory})
    : _inventory = inventory;

  final InventoryRepository _inventory;

  String _name = '';
  String _quantity = '';
  String _unit = defaultUnit;
  StorageLocation _storage = StorageLocation.fridge;
  DateKind _dateKind = DateKind.sellBy;
  DateTime? _dateValue;

  bool _saving = false;
  IngredientBatch? _added;
  Object? _error;

  /// 보내는 중인 넣기의 요청 ID.
  ///
  /// 실패해도 버리지 않는다. 재시도가 새 ID 로 가면 같은 재료가 두 묶음으로 쌓인다.
  String? _requestId;

  static const _uuid = Uuid();

  /// 처음 고른 단위. 냉장고 재료는 대부분 개수로 센다.
  static const defaultUnit = 'ea';

  String get name => _name;
  String get quantity => _quantity;

  /// 고른 단위 기호. `Strings.units` 의 키다.
  String get unit => _unit;
  StorageLocation get storage => _storage;
  DateKind get dateKind => _dateKind;
  DateTime? get dateValue => _dateValue;
  bool get saving => _saving;

  /// 넣은 묶음. 있으면 화면이 닫힌다.
  IngredientBatch? get added => _added;

  Object? get error => _error;

  /// 넣을 수 있는지. 이름과 0 보다 큰 수량이 있어야 한다 — 서버는 잔량 없는 묶음을
  /// 저장하지 않는다.
  bool get ready => _name.trim().isNotEmpty && _parsedQuantity != null;

  void setName(String value) {
    _name = value;
    notifyListeners();
  }

  void setQuantity(String value) {
    _quantity = value;
    notifyListeners();
  }

  void selectUnit(String value) {
    if (_unit == value) return;
    _unit = value;
    notifyListeners();
  }

  void selectStorage(StorageLocation value) {
    if (_storage == value) return;
    _storage = value;
    notifyListeners();
  }

  void selectDateKind(DateKind value) {
    if (_dateKind == value) return;
    _dateKind = value;
    notifyListeners();
  }

  void selectDate(DateTime value) {
    _dateValue = DateTime(value.year, value.month, value.day);
    notifyListeners();
  }

  /// 날짜를 비운다. 모르는 기한을 짐작해 넣지 않는다.
  void clearDate() {
    if (_dateValue == null) return;
    _dateValue = null;
    notifyListeners();
  }

  /// 재료를 넣는다.
  ///
  /// IMPORTANT: 요청 ID 를 만들어 보내고 **실패해도 그 ID 를 버리지 않는다.**
  Future<void> save() async {
    final quantity = _parsedQuantity;
    if (_saving || quantity == null || _name.trim().isEmpty) return;

    _saving = true;
    _error = null;
    notifyListeners();
    try {
      final id = _requestId ??= _uuid.v4();
      _added = await _inventory.addBatch(
        BatchDraft(
          commandId: id,
          name: _name.trim(),
          quantity: quantity,
          unit: _unit,
          storage: _storage,
          dateKind: _dateKind,
          dateValue: _dateValue,
        ),
      );
      _requestId = null;
    } catch (error) {
      _error = error;
      debugPrint('batch add failed: $error');
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// 서버에 보낼 수량. 숫자가 아니거나 0 이하면 `null`.
  String? get _parsedQuantity {
    final raw = _quantity.trim();
    final value = num.tryParse(raw);
    if (value == null || value.isNaN || value.isInfinite || value <= 0) {
      return null;
    }
    return raw;
  }
}
