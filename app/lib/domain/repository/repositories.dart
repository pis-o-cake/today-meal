/// 저장소 계약.
///
/// 인터페이스가 `domain`, 구현이 `data` 에 있다. ViewModel 은 구현을 모른다.
///
/// **수량 계산과 날짜 비교를 앱에 두지 않는다.** 같은 규칙이 앱과 서버 양쪽에 생기면
/// 어느 쪽이 맞는지 판정할 수 없다.
library;

import '../model/change_record.dart';
import '../model/inventory.dart';
import '../model/menu.dart';


abstract interface class InventoryRepository {
  /// 가구의 현재 재고.
  Future<List<IngredientBatch>> listBatches();

  /// 먼저 확인할 재료. 기한이 지난 것도 목록에는 남는다.
  Future<List<PriorityBatch>> listPriorityBatches();

  /// 냉장고 전체 컨디션. 등급 계산은 서버가 한다.
  Future<FridgeCondition> condition();
}

abstract interface class CommandRepository {
  /// 전사된 발화를 서버로 보낸다.
  ///
  /// [commandId] 는 발화마다 새로 만드는 멱등 키다. 재시도할 때는 같은 값을 보낸다 —
  /// 서버가 만들면 재고가 두 번 바뀐다.
  Future<CommandOutcome> interpret({
    required String commandId,
    required String utterance,
  });

  /// 명령 묶음 전체를 되돌린다.
  Future<CommandOutcome> undo(String commandId);

  /// 변경 이력.
  Future<List<ChangeRecord>> history({int limit});
}

abstract interface class MenuRepository {
  /// 추천을 새로 받는다. 재고를 바꾸지 않는다.
  Future<List<MenuSuggestion>> createSuggestions({int? servings, int? maxMinutes});

  /// 메뉴 상세. 인분에 맞춰 환산된 값이 온다.
  Future<MenuDetail> detail(int recipeId, {int? servings});

  /// 조리 확인. 같은 추천에 두 번 보내도 재고가 두 번 줄지 않는다.
  Future<CookedResult> markCooked(int suggestionId);
}

/// 서버가 판정한 명령 결과.
class CommandOutcome {
  const CommandOutcome({
    required this.commandId,
    required this.status,
    required this.intent,
    this.spoken,
    this.clarificationQuestion,
    this.undoToken,
    this.changes = const [],
  });

  final String commandId;
  final String status;
  final String intent;

  /// 읽어줄 한 문장. 상세는 화면에 남긴다.
  final String? spoken;

  /// 되물을 한 가지. 있으면 **아직 반영되지 않았다.**
  final String? clarificationQuestion;

  /// 되돌리기 대상.
  final String? undoToken;

  /// 화면에 보여줄 변경 요약.
  final List<CommandChange> changes;

  bool get isApplied => status == 'applied';

  bool get needsClarification => clarificationQuestion != null;
}

/// 명령이 만든 변경 한 줄.
class CommandChange {
  const CommandChange({
    required this.name,
    required this.action,
    this.before,
    this.after,
    this.unit,
  });

  final String name;
  final String action;
  final String? before;
  final String? after;
  final String? unit;

  String get afterLabel => after == null ? '' : '$after${unit ?? ''}';
}
