import '../../domain/model/change_record.dart';
import '../../domain/model/inventory.dart';
import '../../domain/model/menu.dart';
import '../l10n/strings.dart';
import 'tokens.dart';
import 'package:flutter/material.dart';

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

  static Color freshnessColor(Freshness grade) => switch (grade) {
        Freshness.expired => Tokens.creamDim,
        Freshness.urgent => Tokens.alert,
        Freshness.soon => Tokens.warm,
        Freshness.fresh => Tokens.lime,
        Freshness.unknown => Tokens.creamDim,
      };

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
