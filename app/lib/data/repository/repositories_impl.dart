import '../../core/network/api_client.dart';
import '../../domain/model/change_record.dart';
import '../../domain/model/inventory.dart';
import '../../domain/model/menu.dart';
import '../../domain/repository/repositories.dart';
import '../remote/mappers.dart';

/// 원격 구현. 로컬 DB 를 두지 않는다.
///
/// 오프라인 캐시는 이번 범위 밖이다 — 재고 계산이 서버에만 있으므로 캐시를 두면 화면이
/// 옛 잔량을 사실처럼 보여준다.
class RemoteInventoryRepository implements InventoryRepository {
  RemoteInventoryRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<IngredientBatch>> listBatches() async {
    final rows = await _api.listBatches();
    return rows
        .map((e) => batchFromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<PriorityBatch>> listPriorityBatches() async {
    final rows = await _api.listPriorityBatches();
    return rows
        .map((e) => priorityFromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<FridgeCondition> condition() async =>
      conditionFromJson(await _api.condition());
}

class RemoteCommandRepository implements CommandRepository {
  RemoteCommandRepository(this._api);

  final ApiClient _api;

  @override
  Future<CommandOutcome> interpret({
    required String commandId,
    required String utterance,
  }) async {
    final body = await _api.interpret(commandId: commandId, utterance: utterance);
    return _outcome(body);
  }

  @override
  Future<CommandOutcome> undo(String commandId) async =>
      _outcome(await _api.undo(commandId));

  @override
  Future<List<ChangeRecord>> history({int limit = 50}) async {
    final rows = await _api.history(limit: limit);
    return rows
        .map((e) => recordFromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  CommandOutcome _outcome(Map<String, dynamic> body) {
    final screen = body['screen'] as Map<String, dynamic>? ?? const {};
    final changes = (screen['changes'] as List<dynamic>? ?? const [])
        .map((e) => e as Map<String, dynamic>)
        .map(
          (e) => CommandChange(
            name: e['name'] as String? ?? '',
            action: e['action'] as String? ?? '',
            before: e['before'] as String?,
            after: e['after'] as String?,
            unit: e['unit'] as String?,
          ),
        )
        .toList(growable: false);
    return CommandOutcome(
      commandId: body['command_id'] as String? ?? '',
      status: body['status'] as String? ?? 'failed',
      intent: body['intent'] as String? ?? 'unknown',
      spoken: body['spoken'] as String?,
      clarificationQuestion: body['clarification_question'] as String?,
      undoToken: body['undo_token'] as String?,
      changes: changes,
    );
  }
}

class RemoteMenuRepository implements MenuRepository {
  RemoteMenuRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<MenuSuggestion>> createSuggestions({
    int? servings,
    int? maxMinutes,
  }) async {
    final rows = await _api.createSuggestions(
      servings: servings,
      maxMinutes: maxMinutes,
    );
    return rows
        .map((e) => suggestionFromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<MenuDetail> detail(int recipeId, {int? servings}) async =>
      detailFromJson(await _api.recipeDetail(recipeId, servings: servings));

  @override
  Future<CookedResult> markCooked(int suggestionId) async =>
      cookedFromJson(await _api.markCooked(suggestionId));
}
