import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../domain/model/change_record.dart';
import '../../domain/model/inventory.dart';
import '../../domain/model/menu.dart';
import '../../domain/repository/repositories.dart';
import '../remote/mappers.dart';
import '../remote/social_sign_in.dart';

/// 서버 인증.
///
/// 토큰을 [ApiClient] 에 걸어 이후 모든 호출이 그 계정의 가구를 보게 한다. 토큰 자체의
/// 저장은 설정 계층이 한다 — 저장소는 서버와 말하는 일만 맡는다.
///
/// CAUTION: 비밀번호와 토큰을 로그에 남기지 않는다.
class RemoteAuthRepository implements AuthRepository {
  RemoteAuthRepository(this._api, {SocialSignIn social = const NoSocialSignIn()})
      : _social = social;

  final ApiClient _api;
  final SocialSignIn _social;

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String nickname,
  }) =>
      _open(() => _api.signUp(
            email: email,
            password: password,
            nickname: nickname,
          ));

  @override
  Future<EmailAvailability> checkEmail(String email) async {
    try {
      final body = await _api.emailAvailable(email);
      if (body['available'] == true) return EmailAvailability.free;
      return switch (body['reason']) {
        'taken' => EmailAvailability.taken,
        'invalid' => EmailAvailability.invalid,
        _ => EmailAvailability.unknown,
      };
    } on DioException {
      // 확인이 실패해도 가입을 막지 않는다. 판정은 가입 시점의 서버가 한다.
      return EmailAvailability.unknown;
    }
  }

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) =>
      _open(() => _api.signIn(email: email, password: password));

  @override
  Future<AuthResult> signInWith(SocialProvider provider) async {
    if (!_social.supports(provider)) {
      return const AuthResult.failed(AuthFailure.notConnected);
    }

    final token = await _social.tokenFor(provider);
    if (token.cancelled) {
      return const AuthResult.failed(AuthFailure.cancelled);
    }
    final accessToken = token.accessToken;
    if (accessToken == null) {
      return const AuthResult.failed(AuthFailure.unreachable);
    }

    return _open(() => _api.signInWithProvider(
          provider: provider.path,
          accessToken: accessToken,
        ));
  }

  @override
  Future<void> signOut() async {
    try {
      await _api.signOut();
    } on DioException {
      // 서버에 닿지 못해도 이 기기에서는 로그아웃한다. 남은 세션은 만료로 사라진다.
    } finally {
      _api.setToken(null);
    }
  }

  @override
  Future<AuthAccount?> restore(String token) async {
    _api.setToken(token);
    try {
      return _accountFrom(await _api.me());
    } on DioException {
      // 만료·폐기된 토큰이거나 서버에 닿지 못했다. 둘 다 게스트로 떨어뜨린다 —
      // 자기 냉장고를 보고 있다고 믿으면서 남의 데이터를 보게 두지 않는다.
      _api.setToken(null);
      return null;
    }
  }

  /// 세션을 여는 두 경로가 같은 응답을 준다. 실패 해석도 한곳에 둔다.
  Future<AuthResult> _open(
      Future<Map<String, dynamic>> Function() call) async {
    try {
      final body = await call();
      final token = body['access_token'] as String?;
      if (token == null || token.isEmpty) {
        return const AuthResult.failed(AuthFailure.unreachable);
      }
      _api.setToken(token);
      return AuthResult.success(
        token: token,
        account: _accountFrom(body['user'] as Map<String, dynamic>),
      );
    } on DioException catch (error) {
      return AuthResult.failed(_failureOf(error));
    }
  }

  AuthAccount _accountFrom(Map<String, dynamic> json) => AuthAccount(
        userId: json['user_id'] as int,
        householdId: json['household_id'] as int,
        provider: json['provider'] as String? ?? 'email',
        email: json['email'] as String?,
        nickname: json['display_name'] as String?,
      );

  /// 서버 응답을 사용자가 고칠 수 있는 상태로 옮긴다.
  ///
  /// 상태 코드가 정본이다 — 본문 문구는 로케일에 따라 바뀌므로 분기의 근거로 쓰지 않는다.
  AuthFailure _failureOf(DioException error) => switch (error.response?.statusCode) {
        409 => AuthFailure.emailTaken,
        401 => AuthFailure.wrongCredentials,
        422 || 400 => AuthFailure.invalidInput,
        // 서버가 아직 안 붙인 제공자라고 답했다.
        501 => AuthFailure.notConnected,
        _ => AuthFailure.unreachable,
      };
}

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
