import 'package:dio/dio.dart';

import '../config.dart';

/// 서버 호출 클라이언트.
///
/// 엔드포인트의 정본은 서버의 Swagger UI(`/docs`)다. 여기서는 그 계약을 옮기기만 한다.
///
/// 로그인하면 [setToken] 으로 세션 토큰을 걸고 이후 모든 호출이 그 계정의 가구를 본다.
/// 토큰이 없으면 게스트이며 서버가 기본 가구로 처리한다 — 로그인 없이 둘러보는 경로다.
///
/// WARNING: 이전 판본은 `X-User-Id`·`X-Household-Id` 헤더로 가구를 지정했다. 서버가
/// 더는 그 헤더를 읽지 않는다. 가구를 고르는 유일한 방법은 로그인이다.
class ApiClient {
  ApiClient(AppConfig config, {Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: config.apiBaseUrl,
                connectTimeout: const Duration(seconds: 10),
                // 명령 한 번이 모델 호출을 포함하므로 읽기 타임아웃을 넉넉히 둔다.
                receiveTimeout: const Duration(seconds: 60),
                contentType: Headers.jsonContentType,
              ),
            );

  final Dio _dio;

  /// 세션 토큰을 건다. `null` 이면 게스트로 돌아간다.
  ///
  /// CAUTION: 토큰을 로그에 남기지 않는다. 이 값 하나로 계정에 들어갈 수 있다.
  void setToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
      return;
    }
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// 이메일 가입. 성공하면 바로 로그인된 세션을 돌려준다.
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String nickname,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'api/auth/sign-up',
      data: {'email': email, 'password': password, 'nickname': nickname},
    );
    return response.data ?? const {};
  }

  /// 이메일 로그인.
  Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'api/auth/sign-in',
      data: {'email': email, 'password': password},
    );
    return response.data ?? const {};
  }

  /// 로그아웃. 서버의 세션을 끝낸다.
  Future<void> signOut() => _dio.post<void>('api/auth/sign-out');

  /// 저장해 둔 토큰이 아직 유효한지. 유효하지 않으면 401 이 온다.
  Future<Map<String, dynamic>> me() async {
    final response = await _dio.get<Map<String, dynamic>>('api/auth/me');
    return response.data ?? const {};
  }

  /// 서버와 설정 상태. 태블릿·핸드폰의 왕복 확인에 쓴다.
  Future<Map<String, dynamic>> health() async {
    final response = await _dio.get<Map<String, dynamic>>('health');
    return response.data ?? const {};
  }

  /// 현재 재고 묶음.
  Future<List<dynamic>> listBatches({int limit = 200}) async {
    final response = await _dio.get<List<dynamic>>(
      'api/inventory/batches',
      queryParameters: {'limit': limit},
    );
    return response.data ?? const [];
  }

  /// 냉장고 전체 컨디션. 등급 계산은 서버가 한다.
  Future<Map<String, dynamic>> condition() async {
    final response =
        await _dio.get<Map<String, dynamic>>('api/inventory/condition');
    return response.data ?? const {};
  }

  /// 먼저 쓸 재료.
  Future<List<dynamic>> listPriorityBatches() async {
    final response =
        await _dio.get<List<dynamic>>('api/inventory/batches/expiring');
    return response.data ?? const [];
  }

  /// 발화 해석과 실행.
  ///
  /// [commandId] 는 **발화마다 앱이 만든다.** 재시도할 때는 같은 값을 보내야 서버가 중복을
  /// 막는다. 서버가 만들면 재시도를 구분할 수 없다.
  Future<Map<String, dynamic>> interpret({
    required String commandId,
    required String utterance,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'api/command/interpret',
      data: {'command_id': commandId, 'utterance': utterance, 'locale': 'ko'},
    );
    return response.data ?? const {};
  }

  /// 명령 묶음 전체를 되돌린다.
  Future<Map<String, dynamic>> undo(String commandId) async {
    final response =
        await _dio.post<Map<String, dynamic>>('api/command/$commandId/undo');
    return response.data ?? const {};
  }

  /// 변경 이력.
  Future<List<dynamic>> history({int limit = 50}) async {
    final response = await _dio.get<List<dynamic>>(
      'api/command/history',
      queryParameters: {'limit': limit},
    );
    return response.data ?? const [];
  }

  /// 메뉴 추천을 새로 받는다.
  Future<List<dynamic>> createSuggestions({int? servings, int? maxMinutes}) async {
    final response = await _dio.post<List<dynamic>>(
      'api/menu/suggestions',
      queryParameters: <String, dynamic>{
        if (servings != null) 'servings': servings,
        if (maxMinutes != null) 'max_minutes': maxMinutes,
      },
    );
    return response.data ?? const [];
  }

  /// 조리 확인. 같은 추천에 두 번 보내도 재고가 두 번 줄지 않는다.
  Future<Map<String, dynamic>> markCooked(int suggestionId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'api/menu/suggestions/$suggestionId/cooked',
    );
    return response.data ?? const {};
  }

  /// 메뉴 상세.
  Future<Map<String, dynamic>> recipeDetail(int recipeId, {int? servings}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'api/menu/recipes/$recipeId',
      queryParameters: {if (servings != null) 'servings': servings},
    );
    return response.data ?? const {};
  }
}
