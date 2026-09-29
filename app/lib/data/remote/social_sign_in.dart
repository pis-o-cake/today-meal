/// 제공자 SDK 를 감싼다.
///
/// 카카오 SDK 를 이 파일에서만 읽는다. 화면과 저장소는 "토큰을 받았다 / 취소했다 /
/// 실패했다" 만 알면 되고, SDK 타입이 새어 나가면 제공자를 바꿀 때 화면까지 고쳐야 한다.
///
/// **토큰을 검증하지 않는다.** 검증은 서버가 카카오에 직접 물어서 한다 — 앱이 받은
/// 값을 앱이 확인하는 것은 아무것도 보장하지 않는다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import '../../domain/repository/repositories.dart';

/// 제공자에게 토큰을 받아오는 일.
abstract interface class SocialSignIn {
  /// 이 제공자를 쓸 수 있는지. 키가 없으면 거짓이다.
  bool supports(SocialProvider provider);

  /// 제공자 화면을 열고 액세스 토큰을 받는다.
  ///
  /// 사용자가 취소하면 [SocialToken.cancelled] 다. 취소는 오류가 아니다.
  Future<SocialToken> tokenFor(SocialProvider provider);
}

/// 제공자에게 받은 결과.
@immutable
class SocialToken {
  const SocialToken.received(this.accessToken)
      : cancelled = false,
        failed = false;

  const SocialToken.cancelled()
      : accessToken = null,
        cancelled = true,
        failed = false;

  const SocialToken.failed()
      : accessToken = null,
        cancelled = false,
        failed = true;

  /// CAUTION: 로그에 남기지 않는다.
  final String? accessToken;

  /// 사용자가 제공자 화면에서 그만뒀다.
  final bool cancelled;

  /// 제공자가 실패했다. 앱이 고칠 수 없다.
  final bool failed;
}

class KakaoSignIn implements SocialSignIn {
  KakaoSignIn({required String nativeAppKey}) : _key = nativeAppKey {
    if (_key.isNotEmpty) {
      KakaoSdk.init(nativeAppKey: _key);
    }
  }

  final String _key;

  @override
  bool supports(SocialProvider provider) =>
      provider == SocialProvider.kakao && _key.isNotEmpty;

  @override
  Future<SocialToken> tokenFor(SocialProvider provider) async {
    if (!supports(provider)) return const SocialToken.failed();
    try {
      // 카카오톡이 깔려 있으면 앱으로 연다. 계정을 다시 칠 필요가 없다.
      final installed = await isKakaoTalkInstalled();
      final token = installed
          ? await _viaTalk()
          : await UserApi.instance.loginWithKakaoAccount();
      return SocialToken.received(token.accessToken);
    } on PlatformException catch (error) {
      // 사용자가 카카오톡에서 뒤로 갔다. 취소이지 오류가 아니다.
      if (error.code == 'CANCELED') return const SocialToken.cancelled();
      debugPrint('kakao sign-in failed: ${error.code}');
      return const SocialToken.failed();
    } catch (error) {
      debugPrint('kakao sign-in failed: $error');
      return const SocialToken.failed();
    }
  }

  /// 카카오톡으로 로그인한다.
  ///
  /// 톡이 깔려 있어도 실패할 수 있다 — 계정이 로그아웃돼 있거나 톡 버전이 낮은 경우다.
  /// 그때는 웹 계정 로그인으로 넘어간다. 취소는 넘어가지 않고 그대로 올린다.
  Future<OAuthToken> _viaTalk() async {
    try {
      return await UserApi.instance.loginWithKakaoTalk();
    } on PlatformException catch (error) {
      if (error.code == 'CANCELED') rethrow;
      return UserApi.instance.loginWithKakaoAccount();
    } catch (_) {
      return UserApi.instance.loginWithKakaoAccount();
    }
  }
}

/// 제공자를 하나도 쓸 수 없을 때.
///
/// 키가 없는 빌드에서 쓴다. 버튼을 감추지 않고 "준비 중" 으로 답하게 한다.
class NoSocialSignIn implements SocialSignIn {
  const NoSocialSignIn();

  @override
  bool supports(SocialProvider provider) => false;

  @override
  Future<SocialToken> tokenFor(SocialProvider provider) async =>
      const SocialToken.failed();
}
