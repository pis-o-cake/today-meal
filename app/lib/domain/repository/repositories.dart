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


/// 가입·로그인·로그아웃.
///
/// 실패를 예외가 아니라 [AuthFailure] 로 돌려준다 — 이메일이 이미 있는 것과 비밀번호가
/// 틀린 것은 **사용자가 고칠 수 있는 상태**이지 서버 결함이 아니다. 통신 자체가 실패한
/// 경우에만 예외가 오른다.
abstract interface class AuthRepository {
  /// 이메일 가입. 성공하면 바로 로그인된다.
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String nickname,
  });

  /// 이 이메일로 가입할 수 있는지 미리 확인한다.
  ///
  /// **확정이 아니다.** 확인과 가입 사이에 남이 먼저 가입할 수 있으므로 가입 시점에
  /// 서버가 다시 막는다. 화면은 이 값을 "지금 눌러도 될지" 를 알려주는 데만 쓴다.
  Future<EmailAvailability> checkEmail(String email);

  /// 이메일 로그인.
  Future<AuthResult> signIn({required String email, required String password});

  /// 간편 로그인. 처음이면 계정이 만들어진다.
  ///
  /// 제공자 SDK 로 토큰을 받아 서버에 넘긴다. **서버가 제공자에게 직접 물어 확인한다** —
  /// 앱이 사용자 ID 를 만들어 보내지 않는다.
  Future<AuthResult> signInWith(SocialProvider provider);

  /// 서버 세션을 끝낸다.
  Future<void> signOut();

  /// 저장해 둔 토큰이 아직 유효한지 확인하고 계정을 읽는다.
  ///
  /// 유효하지 않으면 `null`. 앱은 그때 게스트로 떨어뜨리고 로그인을 다시 요구한다.
  Future<AuthAccount?> restore(String token);
}

/// 서버가 확인한 계정.
class AuthAccount {
  const AuthAccount({
    required this.userId,
    required this.householdId,
    required this.provider,
    this.email,
    this.nickname,
  });

  final int userId;
  final int householdId;
  final String provider;
  final String? email;
  final String? nickname;
}

/// 가입·로그인의 결과.
///
/// 성공이면 [token] 과 [account] 가 있고, 실패면 [failure] 가 있다. 둘 다 있는 상태는
/// 만들지 않는다.
class AuthResult {
  const AuthResult.success({required this.token, required this.account})
      : failure = null;

  const AuthResult.failed(this.failure)
      : token = null,
        account = null;

  /// 세션 토큰. **서버가 다시 알려주지 않으므로** 앱이 저장한다.
  final String? token;
  final AuthAccount? account;
  final AuthFailure? failure;

  bool get ok => failure == null;
}

/// 간편 로그인 제공자.
///
/// 지금 붙은 것은 카카오뿐이다. 나머지는 화면에 버튼을 두되 누르면 준비 중이라고
/// 말한다 — 감추면 왜 없는지 알 수 없고, 성공으로 넘기면 인증한 것처럼 보인다.
enum SocialProvider {
  kakao,
  google,
  apple;

  /// 서버 경로에 쓰는 이름. `POST /api/auth/sign-in/{provider}`.
  String get path => name;
}

/// 이메일을 쓸 수 있는지.
enum EmailAvailability {
  /// 가입할 수 있다.
  free,

  /// 이미 가입된 이메일이다.
  taken,

  /// 형식이 이메일이 아니다.
  invalid,

  /// 확인하지 못했다. 서버에 닿지 못했거나 응답이 이상하다.
  ///
  /// **막지 않는다.** 확인은 돕는 것이고 판정은 가입 시점의 서버가 한다 — 확인이
  /// 실패했다고 가입 버튼을 잠그면 서버가 잠깐 흔들릴 때 아무도 가입하지 못한다.
  unknown,
}

/// 사용자가 고칠 수 있는 실패.
enum AuthFailure {
  /// 이미 가입된 이메일이다. 가입에만 나온다.
  emailTaken,

  /// 이메일이나 비밀번호가 맞지 않는다. **둘을 구분하지 않는다** — 서버가 구분해
  /// 주지 않으며, 구분하면 가입된 이메일인지 확인할 수 있게 된다.
  wrongCredentials,

  /// 형식이 서버 검사를 통과하지 못했다.
  invalidInput,

  /// 서버에 닿지 못했다.
  unreachable,

  /// 사용자가 제공자 화면에서 취소했다. **오류로 보여주지 않는다.**
  cancelled,

  /// 아직 연동하지 않은 제공자다.
  notConnected,
}

abstract interface class InventoryRepository {
  /// 가구의 현재 재고.
  Future<List<IngredientBatch>> listBatches();

  /// 먼저 확인할 재료. 기한이 지난 것도 목록에는 남는다.
  Future<List<PriorityBatch>> listPriorityBatches();

  /// 냉장고 전체 컨디션. 등급 계산은 서버가 한다.
  Future<FridgeCondition> condition();

  /// 묶음 하나를 화면에서 고친다.
  ///
  /// **보낸 칸만 바뀐다.** 서버가 기록도 함께 남기므로 기록 화면에 나타난다.
  Future<IngredientBatch> editBatch(int batchId, BatchEdit edit);

  /// 묶음을 버린다. 행을 지우지 않고 버린 것으로 표시한다.
  Future<void> discardBatch(int batchId);
}

/// 화면에서 고친 재고.
///
/// 값을 비우는 것과 그대로 두는 것을 구분한다 — `null` 하나로는 "손대지 않았다" 와 "모르는
/// 값으로 되돌려라" 를 구별할 수 없다.
class BatchEdit {
  const BatchEdit({
    this.name,
    this.quantity,
    this.clearQuantity = false,
    this.unit,
    this.storage,
    this.dateKind,
    this.dateValue,
    this.clearDate = false,
  });

  final String? name;
  final String? quantity;

  /// 잔량을 미확인으로 되돌린다. **0 과 다르다** — 0 은 "다 썼다" 는 사실이다.
  final bool clearQuantity;

  final String? unit;
  final StorageLocation? storage;

  /// 고칠 기한의 종류. 날짜만 보내고 종류를 비우면 서버가 무엇을 고칠지 알 수 없다.
  final DateKind? dateKind;

  final DateTime? dateValue;

  /// [dateKind] 의 날짜를 미확인으로 되돌린다.
  final bool clearDate;

  /// 서버가 받는 형태. **값이 있는 칸만 담는다.**
  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (quantity != null) 'quantity': quantity,
        if (clearQuantity) 'clear_quantity': true,
        if (unit != null) 'unit': unit,
        if (storage != null) 'storage_location': storage!.wire,
        if (dateKind != null) 'date_kind': dateKind!.wire,
        if (dateValue != null) 'date_value': _ymd(dateValue!),
        if (clearDate) 'clear_date': true,
      };

  /// `2026-10-03`. 시각을 붙이면 서버가 날짜로 읽지 못한다.
  static String _ymd(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// 바꿀 것이 하나라도 있는지. 없으면 서버를 부르지 않는다.
  bool get isEmpty => toJson().isEmpty;
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

/// 영상 레시피.
abstract interface class VideoRepository {
  /// 유튜브 링크를 조리 단계로 정리한다.
  ///
  /// **재고를 바꾸지 않는다.** 정리만 하며, 차감은 조리를 마쳤을 때 일어난다.
  ///
  /// Throws:
  ///   [VideoFailure] — 링크가 아니거나 읽을 글이 없거나 순서를 찾지 못했다. 세 경우에
  ///   사용자가 할 수 있는 일이 달라 구분한다.
  Future<VideoRecipe> analyze(String url);
}

/// 영상 정리 실패의 이유.
///
/// 원인마다 사용자가 할 일이 다르다 — 링크를 고치거나, 다른 영상을 고르거나, 잠시 뒤에 다시
/// 하거나다. 하나로 뭉치면 무엇을 해야 하는지 알 수 없다.
enum VideoFailure {
  /// 유튜브 링크가 아니다.
  badLink,

  /// 그 영상을 찾을 수 없다.
  notFound,

  /// 읽을 수 있는 설명이나 자막이 없다. 영상을 바꿔야 한다.
  noScript,

  /// 요리 영상이 아니거나 순서를 찾지 못했다.
  notRecipe,

  /// 서버나 유튜브에 닿지 못했다. 잠시 뒤에 다시 한다.
  unreachable,

  /// 서버 주소가 없는 빌드다.
  notConnected,
}

/// 영상 정리가 실패했다.
class VideoException implements Exception {
  const VideoException(this.failure);

  final VideoFailure failure;

  @override
  String toString() => 'VideoException(${failure.name})';
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
