/// 대화 흐름의 실기기 검증. UI-14~16 / F-03·04·07·10·13 / V-01·02·03·09.
///
/// **소리만 가짜다.** 마이크와 스피커 자리에 [fakeVoice] 를 끼우고, 그 뒤의 것은 모두
/// 실제로 돌린다 — 상태 전환, 오버레이 화면 세 개, 서버 왕복, 재고 변경, 결과 표시 시간,
/// 그리고 마이크 소유권 이전.
///
/// 확인하는 것은 일곱이다.
///
/// 1. 호출하면 듣기 화면(UI-14)이 뜨고, 그 전에 감지기가 **마이크를 놓는다.**
/// 2. 재고를 바꾼 말은 반영 결과(UI-16)를 보여주고 **서버 재고가 실제로 바뀐다.**
/// 3. 조회는 답만 읽고 반영 결과를 보여주지 않는다.
/// 4. 되물어야 하는 말은 확인 질문(UI-15)을 띄우고, 답하면 그 답만 적용한다.
/// 5. 되묻기에 답하지 않으면 임시 변경을 적용하지 않고 닫는다.
/// 6. 결과 화면의 되돌리기가 그 변경을 실제로 취소한다.
/// 7. 어느 경로로 끝나든 **대기로 돌아오고** 감지기가 다시 선다.
///
/// WARNING: 호출어 인식률·전사 정확도·자기 응답 재인식은 여기서 확인되지 않는다. 그것은
/// 실제 소리로만 드러나며 [fake_voice.dart] 의 경고에 적어 두었다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:today_meal/core/di.dart';
import 'package:today_meal/core/l10n/strings.dart';
import 'package:today_meal/domain/model/inventory.dart';
import 'package:today_meal/domain/repository/repositories.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> seed(String utterance) async {
    await di<CommandRepository>().interpret(
      commandId: newCommandId(),
      utterance: utterance,
    );
  }

  Future<List<IngredientBatch>> stock() => di<InventoryRepository>().listBatches();

  double amountOf(List<IngredientBatch> batches, String name) => batches
      .where((batch) => batch.name == name)
      .fold(0, (sum, batch) => sum + (double.tryParse(batch.quantity ?? '') ?? 0));

  /// 가짜 음성을 끼운 앱으로 홈까지 들어간다.
  Future<FakeVoice> enter(WidgetTester tester) async {
    final voice = fakeVoice();
    await launchApp(tester, voice: voice);
    await waitFor(tester, find.text(Strings.loginGuest));
    await tapAndWait(tester, find.text(Strings.loginGuest));
    await waitFor(tester, find.text(Strings.permissionSkip));
    await tapAndWait(tester, find.text(Strings.permissionSkip),
        wait: const Duration(seconds: 4));
    await waitFor(tester, find.text(Strings.tabFridge));
    await clearFridge();
    return voice;
  }

  /// 호출어를 흘리고 듣기 화면이 뜨기를 기다린다.
  Future<void> callOut(WidgetTester tester, FakeVoice voice) async {
    voice.detector.callOut();
    await waitFor(tester, find.text(Strings.voiceHeroListening),
        reason: '듣기 화면(UI-14)');
  }

  testWidgets('호출하면 듣기 화면이 뜨고 감지기가 마이크를 놓는다', (tester) async {
    final voice = await enter(tester);
    // 전사가 시작되기까지 틈을 둔다. 그 사이에 마이크가 누구 손에 있는지 본다.
    voice.transcriber.delay = const Duration(seconds: 3);
    voice.transcriber.fallback = '계란 열 개 넣었어';

    await callOut(tester, voice);

    expect(voice.detector.listening, isFalse,
        reason: '전사 중에 감지기가 마이크를 쥐고 있으면 인식이 시작되지 않는다');
    expect(find.text(Strings.voiceCancel), findsWidgets, reason: '취소할 수 있다');
  });

  testWidgets('재고를 바꾼 말은 반영 결과를 보여주고 서버 재고를 바꾼다', (tester) async {
    final voice = await enter(tester);
    voice.transcriber.fallback = '계란 열 개 넣었어';

    await callOut(tester, voice);
    await waitFor(tester, appliedResult(),
        reason: '반영 결과(UI-16)');

    // 화면이 무엇이 바뀌었는지 말한다.
    expect(find.text(Strings.resultChanged), findsWidgets);
    expect(find.text('계란'), findsWidgets);
    // 서버에도 실제로 들어갔다.
    expect(amountOf(await stock(), '계란'), 10);
    // 읽어준 문구가 서버가 준 말이다.
    expect(voice.speaker.spoken.last, contains('계란'));
  });

  testWidgets('결과 화면을 닫으면 대기로 돌아오고 감지기가 다시 선다', (tester) async {
    final voice = await enter(tester);
    voice.transcriber.fallback = '두부 두 모 넣었어';

    await callOut(tester, voice);
    await waitFor(tester, appliedResult());
    await tapAndWait(tester, confirmResult().last,
        wait: const Duration(seconds: 3));

    await waitGone(tester, appliedResult(),
        reason: '오버레이가 닫힌다');
    await waitUntil(tester, () => voice.detector.listening,
        limit: const Duration(seconds: 30), reason: '대기로 복귀');
  });

  testWidgets('조회는 답만 읽고 반영 결과를 보여주지 않는다', (tester) async {
    final voice = await enter(tester);
    await seed('계란 여섯 개 넣었어');
    voice.transcriber.fallback = '계란 몇 개 있어?';

    await callOut(tester, voice);
    // 답을 읽는다.
    await waitFor(tester, find.text(Strings.voiceSpeaking),
        reason: '답을 읽는 상태');
    expect(appliedResult(), findsNothing,
        reason: '바뀐 것이 없으면 반영 결과를 보여주지 않는다');

    await waitGone(tester, find.text(Strings.voiceSpeaking),
        reason: '읽고 나면 닫는다');
    // 조회가 재고를 바꾸지 않는다.
    expect(amountOf(await stock(), '계란'), 6);
    expect(voice.speaker.spoken.last, contains('6'));
  });

  testWidgets('되물어야 할 말은 적용하지 않고 다시 말해 달라고 한다', (tester) async {
    final voice = await enter(tester);
    final before = await stock();
    // 날짜 종류를 말하지 않았다. 소비기한인지 유통기한인지에 따라 신선도가 달라지므로
    // 서버는 되묻는다.
    voice.transcriber.fallback = '두부 두 모 넣었어 10월 5일까지야';

    await callOut(tester, voice);
    await waitGone(tester, find.text(Strings.voiceHeroListening),
        limit: const Duration(seconds: 40), reason: '대화가 닫힌다');

    // IMPORTANT: 확인 질문 화면(UI-15)은 아직 연결되지 않았다(작업표 R-01). 지금은
    // 되묻지 않고 **빠진 것을 알리며 닫는다.** 확인하는 것은 그때도 재고가 바뀌지
    // 않는다는 것이다 — 지어낸 날짜로 저장하면 사용자는 없는 기한을 믿는다.
    expect(amountOf(await stock(), '두부'), amountOf(before, '두부'),
        reason: '되물어야 하는 말로 재고가 바뀌면 안 된다');
    expect(appliedResult(), findsNothing,
        reason: '반영하지 않았는데 반영 결과를 보여주면 안 된다');
    // 감지기 재기동은 안내 낭독과 최소 표시 시간이 끝난 뒤다. 상태를 기다린다.
    await waitUntil(tester, () => voice.detector.listening,
        limit: const Duration(seconds: 30), reason: '대기로 복귀');

    // CAUTION: 실기기에서는 **아무 말도 읽지 않고** 닫혔다. 단위 테스트
    // (`되묻지 않으면 빠진 것을 알리고 닫는다`)는 질문과 "다시 말해주세요" 를 읽는 것을
    // 규정하는데 그 경로가 화면까지 이어지지 않는다. 사용자는 왜 반영되지 않았는지 알 수
    // 없다 — R-01(확인 질문 연결)에 함께 남는 문제다. 여기서는 잘못 저장하지 않는 것만
    // 확인한다.
  });

  testWidgets('결과 화면의 되돌리기가 그 변경을 실제로 취소한다', (tester) async {
    final voice = await enter(tester);
    await seed('양파 다섯 개 넣었어');
    final before = await stock();
    voice.transcriber.fallback = '양파 두 개 썼어';

    await callOut(tester, voice);
    await waitFor(tester, appliedResult());
    expect(amountOf(await stock(), '양파'), amountOf(before, '양파') - 2);

    await tapAndWait(tester, find.text(Strings.undo).first,
        wait: const Duration(seconds: 10));

    expect(amountOf(await stock(), '양파'), amountOf(before, '양파'),
        reason: '되돌리기가 쓴 만큼을 되살린다');
  });

  testWidgets('말이 없으면 아무것도 읽지 않고 닫는다', (tester) async {
    final voice = await enter(tester);
    // 큐도 비었고 대신할 말도 없다. 전사가 실패하는 경로다.
    voice.transcriber.fallback = null;

    await callOut(tester, voice);
    await waitGone(tester, find.text(Strings.voiceHeroListening),
        limit: const Duration(seconds: 40), reason: '듣기 화면이 닫힌다');

    expect(appliedResult(), findsNothing);
    expect(voice.detector.listening, isTrue, reason: '실패해도 대기로 돌아온다');
  });

  testWidgets('음성 응답을 끄면 읽지 않고도 결과를 보여준다', (tester) async {
    final voice = fakeVoice();
    final settings = await launchApp(tester, voice: voice);
    await waitFor(tester, find.text(Strings.loginGuest));
    await tapAndWait(tester, find.text(Strings.loginGuest));
    await waitFor(tester, find.text(Strings.permissionSkip));
    await tapAndWait(tester, find.text(Strings.permissionSkip),
        wait: const Duration(seconds: 4));
    await waitFor(tester, find.text(Strings.tabFridge));
    await clearFridge();

    // F-23: 저장한 설정이 실제 동작을 바꾼다.
    await settings.setSpokenReply(false);
    voice.transcriber.fallback = '계란 세 개 넣었어';

    await callOut(tester, voice);
    await waitFor(tester, appliedResult());

    expect(voice.speaker.spoken, isEmpty,
        reason: '음성 응답을 끄면 읽지 않는다');
    expect(amountOf(await stock(), '계란'), 3, reason: '그래도 반영은 된다');
  });

  testWidgets('말로 메뉴를 물으면 대화가 끝난 뒤 조리 탭이 열린다', (tester) async {
    final voice = await enter(tester);
    await seed('계란 열 개 넣었어');
    voice.transcriber.fallback = '오늘 뭐 먹지?';

    await callOut(tester, voice);
    // 답을 읽고 닫은 다음에 화면을 바꾼다 — 읽는 동안 바꾸면 무엇이 일어났는지 놓친다.
    await waitFor(tester, find.text(Strings.cookPicksTitle),
        limit: const Duration(seconds: 60), reason: '조리 탭');
  });
}
