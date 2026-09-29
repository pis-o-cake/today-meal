import '../../domain/model/change_record.dart';
import '../../domain/model/inventory.dart';
import '../../domain/model/menu.dart';
import '../l10n/strings.dart';
import '../settings/app_settings.dart';
import 'skin.dart';

/// 도메인 값을 화면 문구로 옮긴다.
///
/// 위젯마다 `switch` 를 다시 쓰지 않도록 여기 한 번만 둔다. **색은 여기 없다** — 테마
/// 4종이 같은 등급을 다른 색으로 그리므로 색은 [Skin] 이 갖는다.
abstract final class Labels {
  static String freshness(Freshness grade) => switch (grade) {
        Freshness.expired => Strings.bandExpired,
        Freshness.urgent => Strings.bandUrgent,
        Freshness.soon => Strings.bandSoon,
        Freshness.fresh => Strings.bandFresh,
        Freshness.unknown => Strings.bandUnknown,
      };

  /// 밴드의 중간 길이 이름. 냉장고 타일의 상태 칩에 쓴다.
  ///
  /// 한마디([freshness])는 문장이라 타일에 안 들어가고, 짧은 이름([freshnessShort])
  /// 만으로는 "코앞" 이 무엇의 코앞인지 알 수 없다.
  static String freshnessWord(Freshness grade) => switch (grade) {
        Freshness.expired => Strings.bandWordExpired,
        Freshness.urgent => Strings.bandWordUrgent,
        Freshness.soon => Strings.bandWordSoon,
        Freshness.fresh => Strings.bandWordFresh,
        Freshness.unknown => Strings.bandWordUnknown,
      };

  /// 밴드의 짧은 이름. 거르개 칩처럼 아주 좁은 자리에 쓴다.
  static String freshnessShort(Freshness grade) => switch (grade) {
        Freshness.expired => Strings.bandShortExpired,
        Freshness.urgent => Strings.bandShortUrgent,
        Freshness.soon => Strings.bandShortSoon,
        Freshness.fresh => Strings.bandShortFresh,
        Freshness.unknown => Strings.bandShortUnknown,
      };

  static String freshnessHint(Freshness grade) => switch (grade) {
        Freshness.expired => Strings.bandExpiredHint,
        Freshness.urgent => Strings.bandUrgentHint,
        Freshness.soon => Strings.bandSoonHint,
        Freshness.fresh => Strings.bandFreshHint,
        Freshness.unknown => Strings.bandUnknownHint,
      };

  /// 메뉴 가용성이 기대는 등급.
  ///
  /// 색을 직접 돌려주지 않고 등급을 돌려준다 — 실제 색은 테마가 정한다.
  static Freshness availabilityBand(MenuAvailability value) => switch (value) {
        MenuAvailability.ready => Freshness.fresh,
        MenuAvailability.needsCheck => Freshness.soon,
        MenuAvailability.needsPurchase => Freshness.urgent,
      };

  static String skinName(SkinName value) => switch (value) {
        SkinName.pastel => Strings.myPageThemePastel,
        SkinName.white => Strings.myPageThemeWhite,
        SkinName.glass => Strings.myPageThemeGlass,
        SkinName.dark => Strings.myPageThemeDark,
      };

  /// 계정을 만든 경로. 마이페이지가 **실제 경로**를 표시해야 한다.
  static String provider(AccountProvider value) => switch (value) {
        AccountProvider.email => Strings.myPageProviderEmail,
        AccountProvider.kakao => Strings.myPageProviderKakao,
        AccountProvider.google => Strings.myPageProviderGoogle,
        AccountProvider.apple => Strings.myPageProviderApple,
        AccountProvider.guest => Strings.myPageGuestKitchen,
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

  /// 재료가 갖춰졌는지. 한 줄 안에 이어 쓸 때의 표현이다.
  ///
  /// [availability] 와 뜻이 같고 말만 다르다. 칩은 좁아서 "지금 가능" 이면 되지만,
  /// "2인분 · 약 15분 · 지금 가능" 은 무엇이 가능하다는 것인지 읽히지 않는다.
  static String stock(MenuAvailability value) => switch (value) {
        MenuAvailability.ready => Strings.menuStockReady,
        MenuAvailability.needsCheck => Strings.menuStockCheck,
        MenuAvailability.needsPurchase => Strings.menuStockShort,
      };

  /// 명령이 만든 변경 한 줄의 동작. 이력과 같은 표를 쓴다.
  static String changeAction(String action) => switch (action) {
        'stock_in' || 'stocked_in' => Strings.historyStockIn,
        'consume' => Strings.historyConsume,
        'adjust' => Strings.historyAdjust,
        'revert' => Strings.historyRevert,
        'discard' => Strings.historyDiscard,
        'move' || 'moved' => Strings.historyMove,
        'split' || 'portioned' => Strings.historySplit,
        'opened' => Strings.historyOpened,
        _ => action,
      };

  /// 기록 한 줄이 무엇을 했는지 한 문장으로.
  ///
  /// 칩은 동작 이름(`보정`)이고 이 문장이 무엇이 일어났는지 말한다. 둘 다 있어야 색을
  /// 못 보는 사람도 읽을 수 있다.
  static String historySaid(ChangeRecord record) => switch (record.action) {
        'stock_in' || 'stocked_in' || 'purchased' => Strings.historySaidStockIn,
        'consume' => Strings.historySaidConsume,
        'adjust' => Strings.historySaidAdjust,
        'correct' => Strings.historySaidAdjust,
        'revert' => Strings.historySaidRevert,
        'discard' => Strings.historySaidDiscard,
        'move' || 'moved' => Strings.historySaidMove,
        'split' || 'portioned' => Strings.historySaidSplit,
        'opened' => Strings.historySaidOpened,
        _ => Strings.historySaidAdjust,
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
