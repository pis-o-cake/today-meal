/// 사용자에게 보이는 문구.
///
/// **위젯에 한국어를 직접 적지 않는다.** 로그와 내부 예외는 영어로 고정하고, 이 파일이
/// 다루는 것은 사용자에게 보이는 문구뿐이다.
///
/// 지금은 한국어만 있다. 언어가 늘면 이 클래스를 인터페이스로 바꾸고 언어별 구현을 둔다.
class Strings {
  const Strings._();

  static const appName = '오늘 뭐 먹지?';

  // 음성 상태. 색만으로 구분하지 않고 문구를 함께 쓴다.
  static const voiceWaiting = '호출 대기 중';
  static const voiceListening = '듣고 있어요';
  static const voiceProcessing = '확인하고 있어요';
  static const voiceSpeaking = '답하고 있어요';
  static const voiceClarifying = '한 가지만 확인할게요';
  static const voiceMuted = '음소거';
  static const voiceSuspended = '앱을 열어두면 불러서 쓸 수 있어요';
  static const voiceUnavailable = '마이크를 쓸 수 없어요';
  static const voiceRetry = '다시 말해주세요';
  static const voiceTapToClose = '탭하면 닫혀요';
  static const voiceDone = '반영했어요';

  /// 되묻기 흐름의 진행 단계.
  static const stepListen = '듣기';
  static const stepConfirm = '확인';
  static const stepApply = '반영';
  static const wakeWordHint = '"자비스, 오늘 뭐 먹지?"';
  // 호출에 바로 답하는 짧은 응답. 불러도 반응이 없으면 안 되는 것으로 보인다.
  static const voiceAck = '네?';

  // 서버 연결
  static const serverChecking = '서버에 연결하는 중';
  static const serverConnected = '서버에 연결됐어요';
  static const serverMissing = '서버 주소가 설정되지 않았어요';
  static const serverFailed = '서버에 연결할 수 없어요';
  static const retry = '다시 시도';

  // 하단 탭
  static const tabToday = '오늘';
  static const tabFridge = '냉장고';
  static const tabHistory = '기록';

  // 신선도 밴드. 등급은 서버가 판정하고 문구만 여기 있다.
  static const bandExpired = '지남';
  static const bandExpiredHint = '오늘 요리 후보에서 뺐어요';
  static const bandUrgent = '급함';
  static const bandUrgentHint = '오늘 안에 쓰세요';
  static const bandSoon = '챙길 것';
  static const bandSoonHint = '이번 주에 쓰세요';
  static const bandFresh = '여유';
  static const bandFreshHint = '급하지 않아요';
  static const bandUnknown = '미확인';
  static const bandUnknownHint = '기한을 알려주세요';
  static String bandCount(int n) => '$n가지';

  /// 아치 안내. 밀거나 눌러 등급을 고른다.
  static const arcHint = '밀어서 재료 상태 보기';

  /// 오늘 날짜 줄. 형식은 화면에서 만들고 여기에는 두지 않는다.
  static const todayGreeting = '오늘 뭐 먹지?';

  // 냉장고 컨디션
  static const conditionRelaxed = '여유';
  static const conditionAttention = '챙길 것';
  static const conditionUrgent = '급함';

  // 메뉴
  static const menuSectionTitle = '오늘은 이 재료로';
  static const menuSectionHint = '이런 메뉴 어떠세요?';
  static const menuReady = '지금 가능';
  static const menuNeedsCheck = '확인 필요';
  static const menuNeedsPurchase = '재료 준비 후';
  static const menuAllIngredients = '재료 다 있음';
  static String menuMinutes(int n) => '약 $n분';
  static String menuServings(int n) => '$n인분';
  static const menuOpen = '보기';
  static String menuOthers(int n) => '다른 메뉴 $n개';
  static const menuNone = '메뉴를 고르는 중';
  static const fridgeOpen = '냉장고에서 확인하기';
  static const dateTell = '기한 말하기';
  static const menuCooked = '해먹었어요';
  static const cookedDone = '반영했어요';
  static const cookedAlready = '이미 반영된 메뉴예요';
  static const cookedSkipped = '양을 몰라 빼지 못한 재료';
  static const menuFindOnCoupang = '쿠팡에서 찾기';
  static const menuSubstitute = '대체 재료로 만들기';
  static const menuIngredients = '재료';
  static const menuSteps = '조리 순서';

  // 냉장고 화면
  static const fridgeSearchHint = '재료 검색';
  static const fridgeAll = '전체';
  static const fridgeSortHint = '급한 것부터';
  static const historyUndoHint = '잘못 반영됐으면 바로 되돌릴 수 있어요';
  static const storageFridge = '냉장';
  static const storageFreezer = '냉동';
  static const storagePantry = '실온';
  static const storageUnknown = '모름';
  static const quantityUnknown = '잔량 미확인';
  static const dateUnknown = '기한 미확인';
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
  static const historyToday = '오늘';
  static const historyUndoable = '되돌릴 수 있어요';
  static const historyStockIn = '입고';
  static const historyConsume = '사용';
  static const historyAdjust = '보정';
  static const historyRevert = '취소';
  static const historyDiscard = '폐기';
  static const historyMove = '이동';
  static const historySplit = '소분';
  static const historyOpened = '개봉';
  static const historyEstimated = '추정';
  static const historyExplicit = '명시값';
  static const historyNoExtraDeduction = '추가 차감 없음';

  // 공통
  static const empty = '아직 등록한 재료가 없어요';
  static const emptyHint = '"자비스"라고 부르고 말해보세요';
  static const undo = '되돌리기';
  static const mute = '음소거';
  static const unmute = '음소거 해제';
  static const micInUse = '마이크 사용 중';
  static const confirmYes = '네, 맞아요';
  static const cancelJustNow = '방금 거 취소';

  // 아직 화면이 없는 자리
  static const uiPending = '화면은 목업 확정 후에 만듭니다';
}
