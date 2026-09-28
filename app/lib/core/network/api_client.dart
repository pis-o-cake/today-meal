import 'package:dio/dio.dart';

import '../config.dart';

/// 서버 호출 클라이언트.
///
/// 엔드포인트의 정본은 서버의 Swagger UI(`/docs`)다. 여기서는 그 계약을 옮기기만 한다.
///
/// 호출자 식별은 `X-User-Id` 헤더로 보낸다. **보안 기능이 아니다** — 서버가 이 값을
/// 검증하지 않으며, 헤더가 없으면 기본 가구로 처리해 로그인 없이도 전 기능이 동작한다.
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

  /// 식별 헤더를 설정한다. 로그인 전에는 부르지 않는다.
  void setCaller({int? userId, int? householdId}) {
    final headers = _dio.options.headers;
    if (userId != null) {
      headers['X-User-Id'] = userId;
    }
    if (householdId != null) {
      headers['X-Household-Id'] = householdId;
    }
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

  /// 메뉴 상세.
  Future<Map<String, dynamic>> recipeDetail(int recipeId, {int? servings}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'api/menu/recipes/$recipeId',
      queryParameters: {if (servings != null) 'servings': servings},
    );
    return response.data ?? const {};
  }
}
