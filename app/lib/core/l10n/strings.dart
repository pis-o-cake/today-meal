/// 사용자에게 보이는 문구.
///
/// **위젯에 한국어를 직접 적지 않는다.** 로그와 내부 예외는 영어로 고정하고, 이 파일이
/// 다루는 것은 사용자에게 보이는 문구뿐이다.
///
/// 지금은 한국어만 있다. 언어가 늘면 이 클래스를 인터페이스로 바꾸고 언어별 구현을 둔다.
library;

import 'particles.dart';

class Strings {
  const Strings._();

  static const appName = '오늘 뭐 먹지?';
  static const appTagline = '말로 관리하는 우리 집 냉장고';

  // 음성 상태. 색만으로 구분하지 않고 문구를 함께 쓴다.
  static const voiceWaiting = '호출 대기 중';
  static const voiceListening = '듣고 있어요';
  static const voiceListeningHint = '말을 마치면 바로 확인해요';
  static const voiceProcessing = '확인하고 있어요';
  static const voiceSpeaking = '답하고 있어요';
  static const voiceClarifying = '한 가지만 확인할게요';
  static const voiceMuted = '음소거';
  static const voiceSuspended = '앱을 열어두면 불러서 쓸 수 있어요';
  static const voiceUnavailable = '마이크를 쓸 수 없어요';
  static const voiceRetry = '다시 말해주세요';
  static const voiceDone = '반영했어요';
  static const voiceTranscribing = '받아 적는 중';

  // 대화 오버레이의 큰 한마디. 상태 칩의 짧은 말과 **다르다** — 칩은 좁은 자리에서
  // 상태를 알리고, 이쪽은 화면을 가득 채워 캐릭터가 말을 거는 자리다.
  static const voiceHeroListening = '쫑긋, 듣고 있어요';
  static const voiceHeroClarifying = '하나만 물어볼게요!';
  static const voiceHeroDone = '싱싱해요!';

  /// 아직 아무 말도 들리지 않았을 때. **예시 문장을 채우지 않는다.**
  static const voiceNothingHeard = '말씀하시면 여기에 적어요';
  static const voiceCancel = '취소';

  /// 호출어. 목업과 권한 안내가 같은 말을 써야 한다.
  static const wakeWord = '헤이 키친';
  static const wakeWordHint = '“헤이 키친”';
  static const wakeWordSetting = '호출어';

  /// 듣는 중 안내.
  ///
  /// 초는 [VoiceSessionManager.commandTimeout] 에서 받는다. 문구에 숫자를 적어 두면
  /// 제한을 바꿀 때 안내만 남아 실제와 달라진다.
  static String micLimitHint(int seconds) =>
      '마이크 사용 중 · $seconds초가 지나면 자동으로 끝나요';

  /// 되묻기 흐름의 진행 단계.
  static const stepListen = '듣기';
  static const stepConfirm = '확인';
  static const stepApply = '반영';
  static const stepListenNow = '듣는 중';
  static const stepConfirmNow = '확인 중';
  static const stepApplyNow = '반영 완료';

  // 호출에 바로 답하는 짧은 응답. 불러도 반응이 없으면 안 되는 것으로 보인다.
  static const voiceAck = '네?';

  /// 확인 질문의 후속 응답 창. 초는 [VoiceSessionManager.clarifyWindow] 에서 받는다.
  static String clarifyWindowHint(int seconds) =>
      '$seconds초 동안은 부르지 않고 바로 말해도 돼요';

  /// 모르는 값을 억지로 채우지 않는다는 제품 규칙.
  static const clarifyKeepUnknown = '모르면 그대로 둘게요. 없는 값을 채우지 않아요';
  static String clarifyAppliedFirst(String name) =>
      '$name${Particles.neun(name)} 먼저 반영했어요';

  /// 반영 결과. 초는 [VoiceSessionManager.resultMinimum] 에서 받는다.
  static String resultReturnHint(int seconds) => '$seconds초 뒤 호출 대기로 돌아가요';
  static const resultConfirm = '확인';
  static const resultChanged = '바뀐 재고';
  static const resultNew = '새로';

  // 서버 연결
  static const serverChecking = '서버에 연결하는 중';
  static const serverFailed = '서버에 연결할 수 없어요';
  static const retry = '다시 시도';

  // 하단 탭. 첫 탭 아이콘은 목업 TabIcons 의 A 수저다.
  static const tabToday = '뭐 먹지?';
  static const tabFridge = '냉장고';
  static const tabCook = '조리';
  static const tabHistory = '기록';
  static const tabMyPage = '마이페이지';

  // 신선도 밴드. 등급은 서버가 판정하고 문구만 여기 있다.
  static const bandExpired = '앗, 기한이 지났어요';
  static const bandExpiredHint = '먹기 전에 상태를 확인해 주세요';
  static const bandUrgent = '기한이 코앞이에요!';
  static const bandUrgentHint = '하루이틀 안에 쓰면 좋아요';
  static const bandSoon = '기한이 며칠 안 남았어요';
  static const bandSoonHint = '이번 주 안에 쓰면 좋아요';
  static const bandFresh = '기한 넉넉해요~';
  static const bandFreshHint = '아직 여유 있어요';
  static const bandUnknown = '기한이 언제예요?';
  static const bandUnknownHint = '기한을 말해 주시면 챙길게요';
  static String bandCount(int n) => '$n가지';

  // 냉장고 상태 거르개의 짧은 이름. 밴드 한마디는 길어 칩에 들어가지 않는다.
  static const bandShortAll = '전체';
  static const bandShortExpired = '지남';
  static const bandShortUrgent = '코앞';
  static const bandShortSoon = '며칠';
  static const bandShortFresh = '넉넉';
  static const bandShortUnknown = '모름';

  /// 아치 안내. 밀거나 눌러 등급을 고른다.
  static const arcHint = '밀어서 재료 상태 보기';

  /// 오늘 날짜 줄. 형식은 화면에서 만들고 여기에는 두지 않는다.
  static const todayGreeting = '오늘 뭐 먹지?';

  // 냉장고 컨디션
  static const conditionRelaxed = '여유';
  static const conditionAttention = '챙길 것';
  static const conditionUrgent = '급함';

  // 메뉴
  static const menuReady = '지금 가능';
  static const menuNeedsCheck = '확인 필요';
  static const menuNeedsPurchase = '재료 준비 후';

  /// 재료가 갖춰졌는지를 **한 줄 안에서** 말할 때. 칩의 짧은 말과 다르다 —
  /// "2인분 · 약 15분 · 지금 가능" 은 무엇이 가능하다는 것인지 읽히지 않는다.
  static const menuStockReady = '재료 다 있어요';
  static const menuStockCheck = '재료 확인 필요';
  static const menuStockShort = '재료 준비 후';
  static String menuMinutes(int n) => '약 $n분';

  /// 추정 시간이라는 사실. 숫자만 두면 보장으로 읽힌다.
  static const menuMinutesCaveat = '조리 환경에 따라 달라요';
  static String menuServings(int n) => '$n인분';
  static const menuServingsLabel = '인분';
  static String menuServingsBasis(int n) => '$n인분 기준';
  static String menuOthers(int n) => '다른 메뉴 $n개';
  static const fridgeOpen = '냉장고에서 확인하기';
  static const dateTell = '기한 말하기';
  static const dateTellExample = '“계란 기한은 10월 20일”';
  static const menuIngredients = '재료';
  static const menuSteps = '조리 순서';
  static const menuHave = '있어요';
  static const menuMissing = '없어요';

  /// 조리 시작. 단계 화면이 화면을 켜 두고 호출어 없이 듣는다.
  static const cookModeStart = '조리 모드 시작';
  static const cookModeStop = '조리 모드 끝내기';
  static const cookModeHint = '단계마다 읽어 주고, 타이머도 말로 맞춰요.\n'
      '다 만들면 쓴 재료를 알아서 빼 둘게요.';

  // 냉장고 화면
  static const fridgeSearch = '재료 검색';
  static const fridgeSearchHint = '재료 이름으로 찾기';
  static const fridgeSearchClear = '검색 지우기';
  static const fridgeSearchEmpty = '찾는 재료가 없어요';
  static const fridgeSearchEmptyHint = '검색이나 보관 위치 필터를 해제해 보세요';
  static const fridgeAll = '전체';
  static const fridgeStatusFilter = '기한 상태로 거르기';

  /// 냉장고 머리말 한 줄. **0 인 항목은 적지 않는다** — 없는 걱정을 만들지 않는다.
  static String fridgeSummary(int total, int urgent, int expired) {
    final parts = <String>['$total가지'];
    if (urgent > 0) parts.add('기한 코앞 $urgent');
    if (expired > 0) parts.add('지남 $expired');
    return parts.join(' · ');
  }
  static const storageFridge = '냉장';
  static const storageFreezer = '냉동';
  static const storagePantry = '실온';
  static const storageUnknown = '모름';
  static const quantityUnknown = '잔량 미확인';
  static const dateTellPlease = '기한을 말해 주세요';
  static const stateCheckNeeded = '상태 확인 필요';
  static String daysLeft(int n) => n < 0 ? '${-n}일 지남' : 'D-$n';
  static String openedDaysAgo(int n) => '개봉 $n일';
  static String itemCount(int n) => '재료 $n종';

  /// 단위 표기.
  ///
  /// 서버는 `ea`·`mo` 처럼 정규화된 기호를 준다. 화면에 그대로 내면 "2mo" 가 보인다.
  /// 모르는 기호는 그대로 돌려준다 — 감추면 값이 사라진 것처럼 보인다.
  static const units = <String, String>{
    'ea': '개',
    'mo': '모',
    'pack': '팩',
    'bunch': '단',
    'sheet': '장',
    'clove': '쪽',
    'g': 'g',
    'kg': 'kg',
    'mg': 'mg',
    'ml': 'ml',
    'l': 'L',
    'cup': '컵',
    'tbsp': '큰술',
    'tsp': '작은술',
  };

  // 기한 종류. 서로 다른 정보이므로 문구도 구분한다.
  static const dateUseBy = '소비기한';
  static const dateSellBy = '유통기한';
  static const dateBestBefore = '품질유지';
  static const dateManufactured = '제조일';
  static const datePacked = '포장일';
  static const dateCheckReminder = '점검 알림';

  // 기록 화면
  static const historyTitle = '기록';
  static const historyUndoHint = '말한 대로 바뀐 내역이에요. 잘못되면 되돌릴 수 있어요';
  static const historyToday = '오늘';
  static const historyUndoFailed = '되돌리지 못했어요';
  static const historyOlderDay = '이전 기록';
  static const historyNewerDay = '다음 기록';
  static const historyEmptyDay = '이 날은 기록이 없어요';
  static const historyStockIn = '입고';
  static const historyConsume = '사용';
  static const historyAdjust = '보정';
  static const historyRevert = '취소';
  static const historyDiscard = '폐기';
  static const historyMove = '이동';
  static const historySplit = '소분';
  static const historyOpened = '개봉';
  static const historyEstimated = '추정';
  static const historyExact = '명시값';

  // 기록 한 줄의 설명. 칩은 동작 이름(위)이고 이 문장이 무엇이 일어났는지 말한다.
  static const historySaidStockIn = '넣은 만큼 채웠어요';
  static const historySaidConsume = '쓴 만큼 뺐어요';
  static const historySaidAdjust = '남은 양을 맞췄어요';
  static const historySaidRevert = '방금 것을 되돌렸어요';
  static const historySaidDiscard = '버린 만큼 뺐어요';
  static const historySaidMove = '보관 위치를 옮겼어요';
  static const historySaidSplit = '나눠 담았어요';
  static const historySaidOpened = '개봉으로 표시했어요';

  /// 수량을 바꾸지 않은 변경. 개봉·이동처럼 상태만 바뀐 기록에 쓴다.
  static const historyNoQuantityChange = '수량 변화 없음';

  // UI-00 스플래시
  static const splashLabel = '오늘 뭐 먹지? 앱을 여는 중';
  static const splashFailed = '앱을 여는 데 실패했어요';

  // UI-01 권한 안내
  static const permissionTitle = '말로 쓰려면\n마이크가 필요해요';
  static const permissionSubtitle = '냉장고 기록을 손 대신 말로 남겨요';
  static const permissionSectionLabel = '필요한 권한';
  static const permissionMic = '마이크';
  static const permissionMicWhy = '“헤이 키친”와 그 뒤의 말을 들어요';
  static const permissionSpeechAndroid = '음성 인식 서비스';
  static const permissionSpeechAndroidWhy =
      '기기에 설정된 음성 인식을 써요. 한국어 음성 데이터가 필요해요';
  static const permissionSpeechIos = '음성 인식';
  static const permissionSpeechIosWhy =
      '말을 글로 바꿔요. Apple 서버에서 처리될 수 있어요';
  static const permissionForeground = '화면이 켜져 있을 때만';
  static const permissionForegroundWhy = '앱을 닫거나 화면이 꺼지면 듣지 않아요';
  static const permissionAllowAndroid = '허용하고 시작하기';
  static const permissionAllowIos = '계속하기';
  static const permissionPromptAndroid = '다음에 허용 창이 한 번 떠요';
  static const permissionPromptIos = '다음에 허용 창이 두 번 떠요 · 마이크, 음성 인식';
  static const permissionSkip = '마이크 없이 둘러보기';
  static const permissionDeniedTitle = '마이크를 허용하지 않았어요';
  static const permissionDeniedHint = '설정에서 허용하면 말로 쓸 수 있어요. 지금은 조회만 돼요';
  static const permissionOpenSettings = '설정 열기';

  // UI-09 로그인
  static const loginEmail = '이메일';
  static const loginEmailHint = 'example@email.com';
  static const loginPassword = '비밀번호';
  static const loginPasswordHint = '비밀번호 입력';
  static const loginSubmit = '로그인';
  static const loginForgot = '비밀번호 찾기';
  static const loginSignUp = '회원가입';
  static const loginSocialDivider = '또는 간편 로그인';
  static const loginKakao = '카카오 로그인';
  static const loginGoogle = 'Google 계정으로 로그인';
  static const loginApple = 'Apple로 로그인';
  static const loginGuest = '로그인 없이 둘러보기';
  static const loginShowPassword = '비밀번호 보기';
  static const loginHidePassword = '비밀번호 숨기기';
  static const loginPasswordEmpty = '비밀번호를 입력해 주세요';

  /// 로그인 실패.
  ///
  /// IMPORTANT: 이메일이 없는 것과 비밀번호가 틀린 것을 **한 문구로** 말한다. 서버가
  /// 구분해 주지 않으며, 구분해 보여주면 아무나 가입된 이메일인지 확인할 수 있다.
  static const loginWrongCredentials = '이메일이나 비밀번호가 맞지 않아요';

  /// 아직 연동하지 않은 경로.
  ///
  /// IMPORTANT: 제공자 토큰을 검증할 수단이 없어 소셜 로그인을 성공으로 처리하지
  /// 않는다. 버튼을 감추지 않고 **왜 안 되는지** 말한다.
  static const loginProviderPending = '아직 연결하지 않은 로그인이에요';
  static const loginProviderPendingHint = '지금은 이메일 가입이나 둘러보기로 시작할 수 있어요';

  // UI-10 회원가입
  static const signUpTitle = '회원가입';
  static const signUpBack = '뒤로';
  static const signUpNickname = '닉네임';
  static const signUpNicknameHint = '냉장고 친구가 불러 줄 이름';
  static const signUpPasswordHint = '8자 이상 입력';
  static const signUpConfirm = '비밀번호 확인';
  static const signUpConfirmHint = '한 번 더 입력';
  static const signUpSubmit = '가입하기';
  static const signUpHaveAccount = '이미 계정이 있나요?';
  static const signUpRuleLetter = '영문';
  static const signUpRuleDigit = '숫자';
  static const signUpRuleLength = '8자 이상';
  static const signUpAgreeAll = '약관에 모두 동의해요';
  static const signUpTermsGroup = '약관 동의';
  static const signUpTermsRequired = '[필수]';
  static const signUpTermsOptional = '[선택]';
  static const signUpTermsService = '서비스 이용약관';
  static const signUpTermsPrivacy = '개인정보 수집·이용';
  static const signUpTermsAlert = '기한 알림 받기';
  static String signUpTermsOpen(String name) => '$name 보기';
  static const signUpErrorNickname = '닉네임을 입력해 주세요';
  static const signUpErrorEmail = '이메일 형식이 맞지 않아요';
  static const signUpErrorPassword = '영문과 숫자를 넣어 8자 이상으로 해주세요';
  static const signUpErrorConfirm = '비밀번호가 서로 달라요';
  static const signUpErrorTaken = '이미 가입된 이메일이에요';
  static const signUpEmailFree = '쓸 수 있는 이메일이에요';

  /// 약관 본문이 아직 없다는 사실.
  ///
  /// 목업의 링크는 자기 화면을 다시 열지만, 그것을 "본문을 보여줬다" 로 쓰지 않는다.
  static const termsPending = '약관 본문은 아직 준비 중이에요';

  // UI-11 마이페이지
  static const myPageTitle = '마이페이지';
  static String myPageKitchen(String nickname) => '$nickname님의 부엌';
  static const myPageGuestKitchen = '게스트로 둘러보는 중';
  static const myPageGuestHint = '로그인하면 이 기기의 설정을 계정에 남겨요';
  static const myPageSignIn = '로그인하기';
  static String myPageSignedInWith(String provider) =>
      '$provider${Particles.ro(provider)} 로그인했어요';
  static const myPageProviderEmail = '이메일';
  static const myPageProviderKakao = '카카오 계정';
  static const myPageProviderGoogle = 'Google 계정';
  static const myPageProviderApple = 'Apple 계정';
  static const myPageThemeSection = '화면 테마';
  static const myPageThemePastel = '파스텔';
  static const myPageThemeWhite = '화이트';
  static const myPageThemeGlass = '글래스';
  static const myPageThemeDark = '다크';
  static const myPageVoiceSection = '음성';
  static const myPageSpokenReply = '음성으로 대답하기';
  static const myPageMealSection = '식사';
  static const myPageDefaultServings = '기본 인분';
  static const myPagePantryStaples = '늘 있는 양념';
  static const myPageAvoided = '피하는 재료';
  static const myPageAlertSection = '알림';
  static const myPageExpiryAlert = '기한 알림';
  static const myPageAlertTiming = '알림 시점';
  static const myPageAccountSection = '계정';
  static const myPageSignOut = '로그아웃';

  /// 아직 화면이 없는 설정 항목.
  static const settingPending = '다음 단계에서 열어요';

  // 조리 탭
  static const cookTitle = '조리';
  static const cookSubtitle = '단계별로 읽어 주고 타이머도 맞춰요';
  static const cookPicksBadge = 'AI 추천';
  static const cookPicksTitle = '냉장고 재료로 요리하기';
  static const cookPicksEmpty = '추천할 요리를 아직 못 골랐어요';
  static const cookStart = '시작';
  static const cookVideoTitle = '영상 레시피로 요리하기';
  static const cookVideoHint = '유튜브 링크를 넣으면 단계별로 정리해 드려요';
  static const cookVideoField = '유튜브 링크';
  static const cookVideoPlaceholder = '링크 붙여넣기';
  static const cookVideoSubmit = '정리하기';
  static const cookVideoWorking = '영상을 보고 단계로 정리하는 중';
  static const cookVideoStart = '이 레시피로 조리 시작';
  static const cookVoiceHint = '“헤이 키친, 두부로 뭐 해 먹지?”';

  /// 영상 레시피 요약 실패. 원인별로 문구를 나눈다.
  static const cookVideoBadLink = '유튜브 링크가 아닌 것 같아요';
  static const cookVideoNoScript = '이 영상에는 읽을 수 있는 설명이 없어요';
  static const cookVideoFailed = '지금은 정리하지 못했어요';

  static String cookVideoSteps(int steps, int minutes) => '$steps단계 · 약 $minutes분';
  static String cookVideoHave(int have, int total) => '재료 $total개 중 $have개';
  static String cookVideoMissing(String names) => '$names만 없어요';

  // 조리 진행
  static const cookingMode = '조리 모드';
  static const cookingClose = '조리 모드 닫기';
  static const cookingAllSteps = '전체 단계 보기';
  static const cookingReading = '읽어 주는 중';
  static const cookingNext = '다음 단계';
  static const cookingPrev = '이전';
  static const cookingNextLabel = '다음';
  static const cookingFinish = '다 만들었어요';
  static const cookingPause = '잠깐 멈춤';
  static const cookingResume = '이어서';
  static const cookingPlusMinute = '+1분';
  static const cookingRestart = '처음부터';
  static const cookingNoTimer = '시간이 필요하면 “타이머 3분”이라고 말해요';
  static const cookingHandsFree = '호출어 없이 들어요';
  static const cookingSayNext = '“다음”';
  static const cookingSayAgain = '“다시 읽어 줘”';
  static const cookingSayTimer = '“타이머 3분”';
  static String cookingStepOf(int no, int total) => '$no단계';
  static String cookingStepTotal(int total) => '/ $total';
  static String cookingServings(int n) => '$n인분';

  // 조리 완료
  static const cookDoneTitle = '짠, 다 만들었어요!';
  static const cookDoneUsedTitle = '쓴 재료를 냉장고에서 뺐어요';
  static const cookDoneAuto = '자동 차감';
  static const cookDoneKept = '그대로';
  static const cookDoneVoiceHint = '틀렸으면 “계란은 3개 썼어”라고 말해 주세요';
  static const cookDoneLogged = '기록에도 남겼어요';
  static const cookDoneConfirm = '확인';
  static String cookDoneSummary(String name, int servings, int minutes) =>
      '$name · $servings인분 · $minutes분 걸렸어요';
  static String cookDoneDelta(String before, String after) => '$before → $after';
  static String cookDoneEditLabel(String name) => '$name 뺀 양 고치기';

  // 재료 상세
  static const itemTitle = '재료 정보';
  static const itemDelete = '삭제';
  static const itemBack = '뒤로';
  static const itemFieldName = '이름';
  static const itemFieldQuantity = '수량';
  static const itemFieldStorage = '보관';
  static const itemFieldDateKind = '날짜 종류';
  static const itemFieldDate = '날짜';
  static const itemEditName = '이름 고치기';
  static const itemPickDate = '날짜 고르기';
  static const itemMinus = '수량 줄이기';
  static const itemPlus = '수량 늘리기';
  static const itemSave = '저장';
  static const itemVoiceHint = '말로도 고쳐요 · “두부 기한 10월 5일로 바꿔”';
  static const itemRecipesAll = '모두 보기';
  static const quantityUnknownShort = '모름';
  static String itemDiscardTitle(String name) => '$name${Particles.reul(name)} 버릴까요?';
  static const itemDiscardBody = '기록에는 남아요. 되돌리려면 다시 등록해야 해요.';
  static String itemRecipesTitle(String name) =>
      '$name${Particles.ro(name)} 만들 수 있어요';
  static String itemDetail(String kind, String date, String remain) =>
      '$kind $date · $remain';

  // 공통
  static const empty = '아직 등록한 재료가 없어요';
  static const emptyHint = '“헤이 키친”이라고 부르고 말해보세요';
  static const undo = '되돌리기';
  static const mute = '음소거';
  static const unmute = '음소거 해제';
  static const close = '닫기';
  static const cancel = '취소';
  static const confirm = '확인';
}
