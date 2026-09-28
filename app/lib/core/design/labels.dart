import '../../domain/model/change_record.dart';
import '../../domain/model/inventory.dart';
import '../../domain/model/menu.dart';
import '../l10n/strings.dart';
import 'package:flutter/material.dart';

import 'band.dart';

/// 도메인 값을 화면 문구와 색으로 옮긴다.
///
/// 위젯마다 `switch` 를 다시 쓰지 않도록 여기 한 번만 둔다. **색만으로 상태를 구분하지
/// 않으므로** 색과 문구를 항상 함께 돌려준다.
abstract final class Labels {
  static String freshness(Freshness grade) => switch (grade) {
        Freshness.expired => Strings.bandExpired,
        Freshness.urgent => Strings.bandUrgent,
        Freshness.soon => Strings.bandSoon,
        Freshness.fresh => Strings.bandFresh,
        Freshness.unknown => Strings.bandUnknown,
      };

  static String freshnessHint(Freshness grade) => switch (grade) {
        Freshness.expired => Strings.bandExpiredHint,
        Freshness.urgent => Strings.bandUrgentHint,
        Freshness.soon => Strings.bandSoonHint,
        Freshness.fresh => Strings.bandFreshHint,
        Freshness.unknown => Strings.bandUnknownHint,
      };

  /// 등급의 강조색. [Bands] 가 정본이므로 여기서 값을 다시 적지 않는다.
  static Color freshnessColor(Freshness grade) => Bands.of(grade).accent;

  /// 등급의 옅은 배경. 칩처럼 색 판이 필요한 곳에 쓴다.
  static Color freshnessSurface(Freshness grade) => Bands.of(grade).bgEdge;

  /// 메뉴 가용성 색. 바로 가능/확인 필요/재료 준비 순으로 신호를 낮춘다.
  static Color availabilityColor(MenuAvailability value) => switch (value) {
        MenuAvailability.ready => Bands.fresh.accent,
        MenuAvailability.needsCheck => Bands.soon.accent,
        MenuAvailability.needsPurchase => Bands.urgent.accent,
      };

  /// 단위 기호를 한국어 표기로. 모르는 기호는 그대로 쓴다.
  static String unit(String? symbol) {
    if (symbol == null || symbol.isEmpty) return '';
    return Strings.units[symbol] ?? symbol;
  }

  /// 재료 한 개의 양. 잔량을 모르면 정성 표현을, 그것도 없으면 빈 문자열을 준다.
  ///
  /// **추정값을 확정값처럼 쓰지 않는다** — 확실하지 않은 수량은 여기서 내보내지 않고
  /// 호출자가 [Strings.quantityUnknown] 을 붙인다.
  static String amount(IngredientBatch batch) {
    if (batch.quantityUncertain) return batch.qualitativeAmount ?? '';
    final quantity = batch.quantity;
    if (quantity == null) return batch.qualitativeAmount ?? '';
    return '${number(quantity)}${unit(batch.unit)}';
  }

  /// 서버가 준 수량 문자열을 사람이 읽는 형태로.
  ///
  /// `NUMERIC` 을 그대로 직렬화하면 `10.000` 처럼 온다. 화면에 그대로 내면 계란이
  /// 10.000개가 된다. 소수부가 의미 있는 값(`0.5`)은 지우지 않는다.
  static String number(String raw) {
    if (!raw.contains('.')) return raw;
    final trimmed = raw.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.endsWith('.')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  static String condition(Condition value) => switch (value) {
        Condition.relaxed => Strings.conditionRelaxed,
        Condition.attention => Strings.conditionAttention,
        Condition.urgent => Strings.conditionUrgent,
      };

  static String storage(StorageLocation value) => switch (value) {
        StorageLocation.fridge => Strings.storageFridge,
        StorageLocation.freezer => Strings.storageFreezer,
        StorageLocation.pantry => Strings.storagePantry,
        StorageLocation.unknown => Strings.storageUnknown,
      };

  /// 기한 종류. **서로 변환하지 않으므로 문구도 구분한다.**
  static String dateKind(DateKind value) => switch (value) {
        DateKind.useBy => Strings.dateUseBy,
        DateKind.sellBy => Strings.dateSellBy,
        DateKind.bestBefore => Strings.dateBestBefore,
        DateKind.manufactured => Strings.dateManufactured,
        DateKind.packed => Strings.datePacked,
        DateKind.checkReminder => Strings.dateCheckReminder,
      };

  static String availability(MenuAvailability value) => switch (value) {
        MenuAvailability.ready => Strings.menuReady,
        MenuAvailability.needsCheck => Strings.menuNeedsCheck,
        MenuAvailability.needsPurchase => Strings.menuNeedsPurchase,
      };

  static String historyAction(ChangeRecord record) => switch (record.action) {
        'stock_in' => Strings.historyStockIn,
        'consume' => Strings.historyConsume,
        'adjust' => Strings.historyAdjust,
        'revert' => Strings.historyRevert,
        'discard' => Strings.historyDiscard,
        'move' || 'moved' => Strings.historyMove,
        'split' || 'portioned' => Strings.historySplit,
        'opened' => Strings.historyOpened,
        'stocked_in' => Strings.historyStockIn,
        _ => record.action,
      };
}
