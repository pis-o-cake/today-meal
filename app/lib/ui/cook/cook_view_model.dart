/// 조리 탭의 상태.
///
/// 두 갈래를 한 화면이 다룬다 — **냉장고 재료로 하는 추천**과 **영상 링크로 하는 정리**다.
/// 둘은 서로 막지 않는다: 추천이 실패해도 링크는 넣을 수 있고, 정리가 실패해도 추천은
/// 남는다. 하나로 묶으면 모델 호출 하나가 화면 전체를 비운다.
library;

import 'package:flutter/foundation.dart';

import '../../domain/model/menu.dart';
import '../../domain/repository/repositories.dart';

class CookViewModel extends ChangeNotifier {
  CookViewModel({
    required MenuRepository menu,
    required VideoRepository video,
    int Function()? defaultServings,
  })  : _menu = menu,
        _video = video,
        _defaultServings = defaultServings;

  final MenuRepository _menu;
  final VideoRepository _video;

  /// 마이페이지에서 고른 기본 인분. 추천 요청에 실어 보낸다.
  final int Function()? _defaultServings;

  bool _loadingPicks = false;
  List<MenuSuggestion> _picks = const [];
  Object? _picksError;
  List<String> _focus = const [];

  bool _summarizing = false;
  VideoRecipe? _recipe;
  VideoFailure? _videoFailure;

  bool get loadingPicks => _loadingPicks;

  /// 냉장고 재료로 만들 수 있는 추천. 지금 가능한 것부터 온다.
  List<MenuSuggestion> get picks => _picks;

  Object? get picksError => _picksError;

  /// 지금 추천이 따른 재료. 말로 지목했을 때만 있다.
  List<String> get focus => _focus;

  /// 영상 링크를 정리하는 중인지. 모델 호출이라 몇 초 걸린다.
  bool get summarizing => _summarizing;

  /// 마지막으로 정리한 영상 레시피.
  VideoRecipe? get recipe => _recipe;

  /// 마지막 정리가 실패한 이유. 성공하면 비워진다.
  VideoFailure? get videoFailure => _videoFailure;

  /// 추천을 읽는다.
  ///
  /// **재고를 바꾸지 않는다.** 서버가 후보를 만들고 가능 여부를 판정해 준다.
  ///
  /// WARNING: 이미 읽는 중이거나 이미 받아 둔 것이 있으면 **다시 부르지 않는다.** 추천은
  /// 모델 호출이고 서버에 호출 간격 제한이 있어, 겹쳐 부르면 뒤의 것이 429 로 거절된다 —
  /// 실기기에서 화면 진입과 탭 전환이 동시에 불러 빈 목록이 나왔다.
  ///
  /// Args:
  ///   force: 이미 받아 둔 것이 있어도 다시 받는다. 사용자가 다시 시도를 누를 때다.
  ///   focus: 사용자가 지목한 재료. 있으면 그 재료가 주재료인 메뉴만 받는다.
  Future<void> loadPicks({
    bool force = false,
    List<String> focus = const [],
  }) async {
    if (_loadingPicks) return;
    // 탭을 오갈 때마다 모델을 다시 부르지 않는다. 다시 받고 싶으면 force 로 부른다.
    if (!force && _picks.isNotEmpty) return;
    _loadingPicks = true;
    _picksError = null;
    _focus = focus;
    notifyListeners();
    try {
      _picks = await _menu.createSuggestions(
        servings: _defaultServings?.call(),
        focus: focus,
      );
    } catch (error) {
      _picks = const [];
      _picksError = error;
      debugPrint('cook picks failed: $error');
    } finally {
      _loadingPicks = false;
      notifyListeners();
    }
  }

  /// 유튜브 링크를 조리 단계로 정리한다.
  ///
  /// 빈 링크는 호출하지 않고 [VideoFailure.badLink] 로 답한다 — 서버를 부를 이유가 없다.
  Future<void> summarize(String url) async {
    if (_summarizing) return;
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      _videoFailure = VideoFailure.badLink;
      notifyListeners();
      return;
    }

    _summarizing = true;
    _videoFailure = null;
    notifyListeners();
    try {
      _recipe = await _video.analyze(trimmed);
    } on VideoException catch (error) {
      // 실패하면 이전 결과를 지운다. 남겨두면 방금 넣은 링크의 결과로 보인다.
      _recipe = null;
      _videoFailure = error.failure;
    } catch (error) {
      _recipe = null;
      _videoFailure = VideoFailure.unreachable;
      debugPrint('video analyze failed: $error');
    } finally {
      _summarizing = false;
      notifyListeners();
    }
  }

  /// 정리 결과와 실패를 비운다. 링크 칸을 지울 때 함께 부른다.
  void clearVideo() {
    if (_recipe == null && _videoFailure == null) return;
    _recipe = null;
    _videoFailure = null;
    notifyListeners();
  }
}
