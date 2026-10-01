/// 재료 상세의 편집 상태.
///
/// 화면이 고친 값을 모아 두고 **저장을 누를 때 한 번** 서버로 보낸다. 칸마다 보내면 연결이
/// 끊긴 상태에서 절반만 저장된 재료가 남는다.
///
/// IMPORTANT: 저장에 성공하지 않으면 **고쳐진 것처럼 그리지 않는다.** 서버가 돌려준 묶음으로
/// 화면을 다시 세운다.
library;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/design/labels.dart';
import '../../domain/model/inventory.dart';
import '../../domain/repository/repositories.dart';

class ItemDetailViewModel extends ChangeNotifier {
  ItemDetailViewModel({
    required IngredientBatch batch,
    required InventoryRepository inventory,
  })  : _batch = batch,
        _inventory = inventory {
    _reset();
  }

  final InventoryRepository _inventory;

  IngredientBatch _batch;

  String _name = '';
  String? _quantity;
  late StorageLocation _storage;
  late DateKind _dateKind;
  DateTime? _dateValue;

  bool _saving = false;
  bool _saved = false;
  bool _discarded = false;
  Object? _error;

  /// 보내는 중인 수정·버리기의 요청 ID.
  ///
  /// 실패해도 버리지 않는다. 재시도가 새 ID 로 가면 서버에 같은 변경이 두 번 쌓인다.
  String? _editRequestId;
  String? _discardRequestId;

  static const _uuid = Uuid();

  /// 서버가 아는 묶음. 저장에 성공하면 갱신된다.
  IngredientBatch get batch => _batch;

  String get name => _name;

  /// 지금 화면의 잔량. 모르면 `null` 이며 숫자를 지어내지 않는다.
  String? get quantity => _quantity;

  StorageLocation get storage => _storage;

  /// 고른 기한 종류. 기본은 서버가 등급 판정에 쓴 종류다.
  DateKind get dateKind => _dateKind;

  DateTime? get dateValue => _dateValue;

  bool get saving => _saving;

  /// 저장에 성공했는지. 화면이 닫히는 조건이다.
  bool get saved => _saved;

  bool get discarded => _discarded;

  Object? get error => _error;

  /// 바꾼 것이 있는지. 없으면 저장 버튼이 서버를 부르지 않는다.
  bool get dirty => !_edit().isEmpty;

  /// 잔량을 하나 줄인다. 0 아래로 내려가지 않는다.
  ///
  /// 잔량을 모르는 묶음에서는 **0 에서 시작하지 않는다** — 모르는 값을 0 으로 단정하는 셈이다.
  /// 대신 아무 일도 하지 않고, 사용자가 숫자를 직접 적게 한다.
  void decrement() {
    final current = _asNumber(_quantity);
    if (current == null) return;
    _setQuantity(current <= 1 ? 0 : current - 1);
  }

  void increment() {
    final current = _asNumber(_quantity);
    _setQuantity((current ?? 0) + 1);
  }

  /// 잔량을 직접 적는다.
  ///
  /// 그램이나 밀리리터는 하나씩 올리고 내려서는 맞출 수 없다. 소수도 받는다("0.5").
  ///
  /// Returns: 받아들였는지. 숫자가 아니거나 음수면 아무것도 바꾸지 않는다.
  bool setQuantity(String raw) {
    final value = num.tryParse(raw.trim());
    if (value == null || value.isNaN || value.isInfinite || value < 0) return false;
    _setQuantity(value);
    return true;
  }

  void rename(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == _name) return;
    _name = trimmed;
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

  /// 고친 내용을 저장한다.
  ///
  /// IMPORTANT: 요청 ID 를 만들어 보내고 **실패해도 그 ID 를 버리지 않는다.** 재시도가
  /// 새 ID 로 가면 서버에 같은 수정이 두 번 쌓인다.
  Future<void> save() async {
    if (_saving) return;
    final edit = _edit();
    if (edit.isEmpty) {
      _saved = true;
      notifyListeners();
      return;
    }

    _saving = true;
    _error = null;
    notifyListeners();
    try {
      final id = _editRequestId ??= _uuid.v4();
      _batch = await _inventory.editBatch(
        _batch.batchId,
        BatchEdit(
          commandId: id,
          name: edit.name,
          quantity: edit.quantity,
          clearQuantity: edit.clearQuantity,
          unit: edit.unit,
          storage: edit.storage,
          dateKind: edit.dateKind,
          dateValue: edit.dateValue,
          clearDate: edit.clearDate,
        ),
      );
      _editRequestId = null;
      _reset();
      _saved = true;
    } catch (error) {
      _error = error;
      debugPrint('batch edit failed: $error');
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// 이 재료를 버린다.
  Future<void> discard() async {
    if (_saving) return;
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      final id = _discardRequestId ??= _uuid.v4();
      await _inventory.discardBatch(_batch.batchId, commandId: id);
      _discardRequestId = null;
      _discarded = true;
    } catch (error) {
      _error = error;
      debugPrint('batch discard failed: $error');
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// 서버가 아는 잔량. 표시와 비교에 같은 형태를 쓴다.
  String? get _stored {
    final raw = _batch.quantity;
    return raw == null ? null : Labels.number(raw);
  }

  /// 서버에 보낼 변경. **달라진 칸만** 담는다.
  BatchEdit _edit() => BatchEdit(
        name: _name == _batch.name ? null : _name,
        quantity: _quantity == _stored ? null : _quantity,
        unit: _quantity == _stored ? null : _batch.unit,
        storage: _storage == _batch.storage ? null : _storage,
        dateKind: _dateChanged ? _dateKind : null,
        dateValue: _dateChanged ? _dateValue : null,
      );

  /// 날짜가 달라졌는지. 종류만 바꾼 경우도 저장 대상이다.
  bool get _dateChanged {
    if (_dateValue == null) return false;
    final stored = _storedDate(_dateKind);
    return stored == null || !_sameDay(stored, _dateValue!);
  }

  void _setQuantity(num value) {
    // `3.0` 으로 적으면 서버가 준 `3` 과 달라 바꾸지 않았는데도 저장 대상이 된다.
    _quantity = Labels.number(value.toString());
    notifyListeners();
  }

  /// 화면 상태를 서버가 아는 값으로 되돌린다.
  ///
  /// WARNING: 서버의 `NUMERIC` 은 `8.000` 으로 온다. 그대로 두면 화면에 소수점이 보이고,
  /// 바꾸지 않았는데도 `8` 과 달라 저장 대상이 된다.
  void _reset() {
    _name = _batch.name;
    _quantity = _stored;
    _storage = _batch.storage;
    // 소비기한은 고를 수 없는 갈래다. 같은 말(유통기한)로 보여준다.
    final kind = _batch.expiryKind ?? _firstKind() ?? DateKind.sellBy;
    _dateKind = kind == DateKind.useBy ? DateKind.sellBy : kind;
    _dateValue = _storedDate(_dateKind);
  }

  DateKind? _firstKind() => _batch.dates.firstOrNull?.kind;

  /// 저장된 날짜. 서버는 `2026-10-03` 문자열로 준다.
  ///
  /// 읽을 수 없는 값은 `null` 로 둔다 — 짐작한 날짜를 화면에 세우지 않는다.
  DateTime? _storedDate(DateKind kind) {
    for (final row in _batch.dates) {
      if (row.kind != kind) continue;
      final raw = row.value;
      return raw == null ? null : DateTime.tryParse(raw);
    }
    return null;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 잔량 문자열을 수로. 소수 잔량(`0.5`)도 하나씩 올리고 내린다.
  static num? _asNumber(String? raw) => raw == null ? null : num.tryParse(raw);
}
