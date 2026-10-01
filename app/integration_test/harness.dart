/// 실기기 통합 검증의 공통 배선.
///
/// 위젯 테스트는 가짜 저장소를 쓰므로 **배선을 확인하지 못한다.** 여기서는 실제 기기에서
/// 실제 앱을 띄우고 실제 서버와 왕복한다 — DI·플랫폼 채널·직렬화·화면 전환이 함께 걸린다.
///
/// 서버 주소는 `--dart-define=E2E_BASE_URL=...` 로 받는다. 값이 없으면 `.env` 를 쓴다.
/// **검증용 서버를 따로 띄워 쓴다** — 모델 호출 비용이 들지 않고 결과가 흔들리지 않는
/// 가짜 게이트웨이 서버를 쓰는 것이 이 파일의 전제다. 시연 DB 에 테스트 데이터를 남기지
/// 않기 위한 것이기도 하다.
///
/// 호출어 감지는 끈다. 마이크를 잡으면 기기의 권한 창이 테스트를 멈춘다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:today_meal/core/config.dart';
import 'package:today_meal/core/di.dart';
import 'package:today_meal/core/l10n/strings.dart';
import 'package:today_meal/core/settings/app_settings.dart';
import 'package:today_meal/core/voice/voice_session_manager.dart';
import 'package:today_meal/domain/repository/repositories.dart';
import 'package:today_meal/main.dart';

import 'fake_voice.dart';

/// 검증용 서버 주소. 빌드 때 넣는다.
const _definedBaseUrl = String.fromEnvironment('E2E_BASE_URL');

/// 화면 하나가 뜨기를 기다리는 한계.
///
/// 실기기에서 서버 왕복이 끼면 `pumpAndSettle` 의 기본 한계로는 모자란다. 추천은 모델
/// 경로라 더 느리다.
const settleLimit = Duration(seconds: 30);

/// 이 검증이 쓸 설정.
///
/// 저장소를 **비우고 시작한다.** 앞선 테스트가 남긴 로그인·테마가 남아 있으면 첫 진입
/// 흐름을 확인할 수 없다.
Future<AppSettings> freshSettings() async {
  final store = await SharedPreferences.getInstance();
  await store.clear();
  return AppSettings.load();
}

/// 가짜 음성 계층을 끼운 결과. 테스트가 호출어를 흘려보내고 읽은 말을 본다.
typedef FakeVoice = ({
  FakeDetector detector,
  FakeTranscriber transcriber,
  FakeSpeaker speaker,
});

/// 앱을 띄운다.
///
/// [settings] 를 주면 그 상태에서 시작한다 — 로그인·권한 안내를 이미 지난 상태로 두고
/// 탭 화면만 확인할 때 쓴다.
///
/// [voice] 를 주면 마이크·스피커 자리에 그것을 끼운다. 대화 흐름을 소리 없이 확인할 때
/// 쓴다 — 만드는 것은 [fakeVoice] 다.
Future<AppSettings> launchApp(
  WidgetTester tester, {
  AppSettings? settings,
  FakeVoice? voice,
}) async {
  await dotenv.load(fileName: '.env', isOptional: true);
  await initializeDateFormatting('ko');

  final resolved = settings ?? await freshSettings();
  final baseUrl = _definedBaseUrl.isNotEmpty
      ? _definedBaseUrl
      : (dotenv.maybeGet('API_BASE_URL') ?? '');
  expect(
    baseUrl,
    isNotEmpty,
    reason: '서버 주소가 없다. --dart-define=E2E_BASE_URL=http://<host>:<port>/ 로 넣는다',
  );

  await di.reset();
  await registerDependencies(
    AppConfig(
      apiBaseUrl: baseUrl,
      // 마이크를 잡지 않는다. 권한 창이 뜨면 테스트가 그 자리에서 멈춘다.
      wakeWordEnabled: false,
    ),
    settings: resolved,
  );

  if (voice != null) {
    // IMPORTANT: 세션 매니저를 통째로 갈아 끼운다. 전사기와 낭독기는 DI 에 없고
    // 매니저가 직접 만들기 때문이다. `ConversationViewModel` 이 만들어지기 **전**에
    // 바꿔야 한다 — 그것이 이 매니저를 붙들고 화면에 잇는다.
    di.unregister<VoiceSessionManager>();
    di.registerSingleton<VoiceSessionManager>(
      VoiceSessionManager(
        detector: voice.detector,
        transcriber: voice.transcriber,
        speaker: voice.speaker,
        retryMessage: Strings.voiceNotApplied,
        ackMessage: Strings.voiceAck,
        checkingMessage: Strings.voiceChecking,
        restartMessage: Strings.voiceSayAgain,
        spokenReply: () => di<AppSettings>().spokenReply,
      ),
    );
  }

  await tester.pumpWidget(TodayMealApp(settings: resolved));
  // WARNING: `pumpAndSettle` 을 쓰지 않는다. 캐릭터가 계속 숨을 쉬므로 애니메이션이
  // 멈추는 순간이 없고, 기다리면 그 자리에서 시간을 다 쓴다.
  await pumpFor(tester, const Duration(seconds: 3));
  return resolved;
}

/// 정해진 시간만큼 프레임을 돌린다.
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 조건이 맞을 때까지 프레임을 돌린다.
///
/// `pumpAndSettle` 은 애니메이션이 끝나기를 기다리지만, 서버 응답을 기다리지는 않는다.
/// 숨 쉬는 캐릭터처럼 **끝나지 않는 애니메이션**이 있는 화면에서는 아예 돌아오지 않는다.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration limit = settleLimit,
  String? reason,
}) async {
  final deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 120));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('${reason ?? finder.describeMatch(Plurality.zero)} 이 $limit 안에 나타나지 않았다');
}

/// 조건이 참이 될 때까지 프레임을 돌린다. 화면이 아닌 상태를 기다릴 때 쓴다.
Future<void> waitUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration limit = settleLimit,
  String? reason,
}) async {
  final deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 120));
    if (done()) return;
  }
  fail('${reason ?? "조건"} 이 $limit 안에 참이 되지 않았다');
}

/// 조건이 사라질 때까지 기다린다.
Future<void> waitGone(
  WidgetTester tester,
  Finder finder, {
  Duration limit = settleLimit,
  String? reason,
}) async {
  final deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 120));
    if (finder.evaluate().isEmpty) return;
  }
  fail('${reason ?? finder.describeMatch(Plurality.zero)} 이 $limit 안에 사라지지 않았다');
}

/// 끝나지 않는 애니메이션이 있는 화면에서도 쓸 수 있는 탭.
///
/// [warn] 을 켜면 빗나간 탭이 경고로 드러난다. 조용히 넘기면 눌리지 않은 것을 화면이
/// 바뀌지 않은 것으로 잘못 읽는다.
Future<void> tapAndWait(
  WidgetTester tester,
  Finder finder, {
  Duration wait = const Duration(seconds: 2),
  bool warn = false,
}) async {
  await tester.tap(finder, warnIfMissed: warn);
  await tester.pump();
  await pumpFor(tester, wait);
}

/// 반영 결과가 떴는지.
///
/// IMPORTANT: 화면이 테마마다 다르다. 글래스는 듣던 화면 안에서 알리고(`반영했어요`) 다른
/// 테마는 전용 결과 화면을 쓴다(`싱싱해요!`). 두 화면이 함께 쓰는 것은 "바뀐 재고" 머리와
/// 확인 버튼이므로 그것으로 찾는다.
Finder appliedResult() => find.text(Strings.resultChanged);

/// 결과를 닫는 확인 버튼.
Finder confirmResult() => find.text(Strings.resultConfirm);

/// 가짜 음성 계층 한 벌.
FakeVoice fakeVoice() => (
      detector: FakeDetector(),
      transcriber: FakeTranscriber(),
      speaker: FakeSpeaker(),
    );

/// 발화마다 새로 만드는 멱등 키.
///
/// 서버는 UUID 를 요구한다 — 아무 문자열을 보내면 422 다.
String newCommandId() => const Uuid().v4();

/// 이 가구의 재고를 모두 버린다.
///
/// 테스트마다 같은 자리에서 시작해야 한다. 앞선 테스트가 남긴 묶음이 쌓이면 검색 0건이나
/// 등급별 개수가 흔들린다. 서버에는 한 번에 비우는 경로가 없으므로 하나씩 버린다.
Future<void> clearFridge() async {
  final inventory = di<InventoryRepository>();
  for (final batch in await inventory.listBatches()) {
    await inventory.discardBatch(batch.batchId, commandId: const Uuid().v4());
  }
}

/// 화면에 보이는 글자를 모두 출력한다. 실패 원인을 좁힐 때 쓴다.
void dumpTexts(String where) {
  final texts = find
      .byType(Text)
      .evaluate()
      .map((element) => (element.widget as Text).data)
      .whereType<String>()
      .where((value) => value.trim().isNotEmpty)
      .toList();
  debugPrint('[$where] ${texts.join(' | ')}');
}

/// 위젯이 보일 때까지 스크롤한다. 목록이 길면 화면 밖에 있다.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable);
  if (scrollable.evaluate().isEmpty) return;
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: scrollable.first,
    maxScrolls: 30,
  );
  await tester.pump();
}
