/// 재고 묶음.
///
/// 같은 두부라도 기한이나 개봉 상태가 다르면 다른 묶음이다. 잔량을 모르는 묶음은 숫자를
/// 지어내지 않고 [quantityUncertain] 으로 드러낸다.
class IngredientBatch {
  const IngredientBatch({
    required this.batchId,
    required this.ingredientId,
    required this.name,
    required this.certainty,
    required this.storage,
    required this.freshness,
    this.quantity,
    this.unit,
    this.qualitativeAmount,
    this.daysLeft,
    this.expiryKind,
    this.quantityUncertain = false,
    this.dates = const [],
  });

  final int batchId;
  final int ingredientId;
  final String name;

  /// 수량. 정성 잔량이면 `null`.
  final String? quantity;
  final String? unit;

  /// `조금`·`반` 같은 표현. 숫자로 바꾸지 않는다.
  final String? qualitativeAmount;

  final QuantityCertainty certainty;
  final StorageLocation storage;

  /// 신선도 등급. **서버가 계산한다.** 앱은 담기만 한다.
  final Freshness freshness;

  /// 표시기한까지 남은 날. 지났으면 음수.
  final int? daysLeft;

  /// 등급 판정에 쓴 기한 종류. 화면이 무엇 때문인지 밝힐 수 있어야 한다.
  final DateKind? expiryKind;

  /// 잔량을 모르거나 추정인지. **신선도와 섞지 않는다.**
  final bool quantityUncertain;

  final List<BatchDate> dates;

  /// 화면에 쓸 잔량 문구. 모르면 모른다고 한다.
  String get amountLabel {
    final value = quantity;
    if (value == null) return qualitativeAmount ?? '';
    return '$value${unit ?? ''}';
  }

  bool get hasAmount => quantity != null || qualitativeAmount != null;
}

/// 수량의 확실성. 명시값과 추정값을 구분한다.
enum QuantityCertainty {
  exact,
  estimated,
  qualitative,
  unknown;

  static QuantityCertainty parse(String? raw) => switch (raw) {
        'exact' => QuantityCertainty.exact,
        'estimated' => QuantityCertainty.estimated,
        'qualitative' => QuantityCertainty.qualitative,
        _ => QuantityCertainty.unknown,
      };
}

/// 보관 위치. 실제 온도 측정값이 아니다.
enum StorageLocation {
  fridge,
  freezer,
  pantry,
  unknown;

  static StorageLocation parse(String? raw) => switch (raw) {
        'fridge' => StorageLocation.fridge,
        'freezer' => StorageLocation.freezer,
        'pantry' => StorageLocation.pantry,
        _ => StorageLocation.unknown,
      };

  /// 서버가 쓰는 값. `parse` 의 역방향이며 둘이 어긋나면 저장이 조용히 무시된다.
  String get wire => switch (this) {
        StorageLocation.fridge => 'fridge',
        StorageLocation.freezer => 'freezer',
        StorageLocation.pantry => 'pantry',
        StorageLocation.unknown => 'unknown',
      };
}

/// 신선도 등급.
///
/// **기한 축만 담는다.** 잔량 미확인은 별도 신호다. 안전 여부를 판정하는 값이 아니다 —
/// [expired] 는 표시기한이 지났다는 사실만 말한다.
enum Freshness {
  fresh,
  soon,
  urgent,
  expired,
  unknown;

  static Freshness parse(String? raw) => switch (raw) {
        'fresh' => Freshness.fresh,
        'soon' => Freshness.soon,
        'urgent' => Freshness.urgent,
        'expired' => Freshness.expired,
        _ => Freshness.unknown,
      };

  /// 오늘 요리 후보로 쓸 수 있는지. 기한이 지난 것은 뺀다.
  bool get isCookable => this != Freshness.expired;
}

/// 묶음의 날짜 한 줄.
class BatchDate {
  const BatchDate({
    required this.kind,
    this.value,
    this.isConfirmed = false,
    this.rawText,
  });

  final DateKind kind;

  /// 날짜. `null` 이면 종류는 알지만 날짜를 모른다는 뜻이다.
  final String? value;

  /// 사용자나 라벨로 확인되었는지. 미확인을 확정값으로 승격하지 않는다.
  final bool isConfirmed;

  final String? rawText;
}

/// 날짜 종류.
///
/// 서로 변환하지 않는다. 제조일을 소비기한으로 승격하지 않으며, [checkReminder] 를
/// 소비기한이나 안전 보증으로 표현하지 않는다.
enum DateKind {
  useBy,
  sellBy,
  bestBefore,
  manufactured,
  packed,
  checkReminder;

  static DateKind? parse(String? raw) => switch (raw) {
        'use_by' => DateKind.useBy,
        'sell_by' => DateKind.sellBy,
        'best_before' => DateKind.bestBefore,
        'manufactured' => DateKind.manufactured,
        'packed' => DateKind.packed,
        'check_reminder' => DateKind.checkReminder,
        _ => null,
      };

  /// 서버가 쓰는 값. `parse` 의 역방향이다.
  String get wire => switch (this) {
        DateKind.useBy => 'use_by',
        DateKind.sellBy => 'sell_by',
        DateKind.bestBefore => 'best_before',
        DateKind.manufactured => 'manufactured',
        DateKind.packed => 'packed',
        DateKind.checkReminder => 'check_reminder',
      };
}

/// 먼저 확인할 묶음.
class PriorityBatch {
  const PriorityBatch({
    required this.batch,
    required this.reason,
    required this.isCookable,
    this.daysLeft,
  });

  final IngredientBatch batch;
  final PriorityReason reason;

  /// 오늘 요리 후보로 쓸 수 있는지. 기한이 지난 항목은 거짓이다.
  final bool isCookable;

  final int? daysLeft;
}

/// 먼저 확인할 이유.
enum PriorityReason {
  expired,
  expiring,
  opened,
  quantityUnknown;

  static PriorityReason parse(String? raw) => switch (raw) {
        'expired' => PriorityReason.expired,
        'expiring' => PriorityReason.expiring,
        'opened' => PriorityReason.opened,
        _ => PriorityReason.quantityUnknown,
      };
}

/// 냉장고 전체 컨디션.
///
/// 화면 맨 위에 한 낱말로 뜬다. **계산은 서버가 한다.**
class FridgeCondition {
  const FridgeCondition({
    required this.condition,
    required this.urgentCount,
    required this.soonCount,
    required this.expiredCount,
    required this.unknownQuantityCount,
    required this.totalCount,
  });

  const FridgeCondition.empty()
      : condition = Condition.relaxed,
        urgentCount = 0,
        soonCount = 0,
        expiredCount = 0,
        unknownQuantityCount = 0,
        totalCount = 0;

  final Condition condition;
  final int urgentCount;
  final int soonCount;
  final int expiredCount;

  /// 잔량을 모르는 묶음 수. 신선도 등급과 섞지 않는다.
  final int unknownQuantityCount;

  final int totalCount;
}

enum Condition {
  relaxed,
  attention,
  urgent;

  static Condition parse(String? raw) => switch (raw) {
        'urgent' => Condition.urgent,
        'attention' => Condition.attention,
        _ => Condition.relaxed,
      };
}
