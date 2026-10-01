/// 냉장고와 재료 상세의 실기기 검증. UI-07·08 / F-06·12·24 / V-06·16.
///
/// 확인하는 것은 다섯이다.
///
/// 1. 서버가 준 재고가 **화면 수량과 같다.**
/// 2. 검색과 보관 위치 필터가 함께 걸리고, 0건을 빈 냉장고와 구분해 말한다.
/// 3. 기한 상태 필터가 등급별로 목록을 바꾼다.
/// 4. 재료 상세에서 고친 수량이 **저장되고 목록에 반영된다.**
/// 5. 그 수정이 기록에 남아 **되돌리면 이전 값으로 복원된다.**
///
/// 재고는 이 테스트가 서버에 직접 넣는다 — 화면에 재고를 넣는 경로는 음성뿐이고, 마이크는
/// 자동화할 수 없다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:today_meal/core/di.dart';
import 'package:today_meal/core/l10n/strings.dart';
import 'package:today_meal/domain/repository/repositories.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 게스트로 홈까지 들어간다.
  ///
  /// 재고를 넣는 경로가 음성뿐이므로 서버에 바로 넣는다. 게스트는 기본 가구를 쓰고,
  /// 검증용 서버의 기본 가구는 이 테스트 전용이다.
  Future<void> enterAsGuest(WidgetTester tester) async {
    await launchApp(tester);
    await waitFor(tester, find.text(Strings.loginGuest));
    await tapAndWait(tester, find.text(Strings.loginGuest));
    await waitFor(tester, find.text(Strings.permissionSkip));
    await tapAndWait(tester, find.text(Strings.permissionSkip),
        wait: const Duration(seconds: 4));
    await waitFor(tester, find.text(Strings.tabFridge));
    await clearFridge();
  }

  /// 냉장고 화면의 표지. 검색은 아이콘 버튼이라 글자가 아니라 접근성 라벨로 찾는다.
  ///
  /// IMPORTANT: 함수로 둔다. 파인더를 미리 만들면 접근성이 켜지기 전에 평가된다.
  Finder fridgeScreen() => find.byTooltip(Strings.fridgeSearch);

  Future<void> openFridge(WidgetTester tester) async {
    await tapAndWait(tester, find.text(Strings.tabFridge).last,
        wait: const Duration(seconds: 6));
    await waitFor(tester, fridgeScreen(), reason: '냉장고 화면');
  }

  /// 발화 하나를 서버로 보낸다. 앱이 쓰는 그 경로다.
  ///
  /// 명령 ID 는 발화마다 새로 만든다 — 같은 값을 보내면 서버가 재시도로 보고 한 번만
  /// 적용한다.
  Future<void> say(String utterance) async {
    await di<CommandRepository>().interpret(
      commandId: newCommandId(),
      utterance: utterance,
    );
  }

  testWidgets('넣은 재고가 냉장고 화면에 그 수량으로 뜬다', (tester) async {
    await enterAsGuest(tester);
    await say('계란 열 개 넣었어');
    await openFridge(tester);

    await waitFor(tester, find.text('계란'), reason: '계란 타일');
    expect(find.textContaining('10'), findsWidgets, reason: '화면 수량이 서버와 같다');
  });

  testWidgets('검색이 걸리고 0건을 빈 냉장고와 구분한다', (tester) async {
    await enterAsGuest(tester);
    await say('두부 두 모 넣었어');
    await openFridge(tester);
    await waitFor(tester, find.text('두부'));

    // 검색은 접혀 있다. 버튼을 눌러 칸을 열고 입력한다.
    await tapAndWait(tester, fridgeScreen());
    await waitFor(tester, find.byType(TextField), reason: '검색 칸');
    final search = find.byType(TextField).first;
    await tester.enterText(search, '두부');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('두부'), findsWidgets);

    await tester.enterText(search, '없는재료이름');
    await waitFor(tester, find.text(Strings.fridgeSearchEmpty),
        reason: '검색 0건');
    // 빈 냉장고 문구가 아니라 검색 0건 문구여야 한다. 둘은 사용자가 할 일이 다르다.
    expect(find.text(Strings.empty), findsNothing);

    await tapAndWait(tester, find.byTooltip(Strings.fridgeSearchClear).last);
    await waitFor(tester, find.text('두부'));
  });

  testWidgets('보관 위치 필터가 목록을 가른다', (tester) async {
    await enterAsGuest(tester);
    await say('계란 다섯 개 냉장에 넣었어');
    await openFridge(tester);
    await waitFor(tester, find.text('계란'));

    // 냉동만 고르면 냉장 재료가 빠진다.
    await tapAndWait(tester, find.text(Strings.storageFreezer).first);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(Strings.fridgeSearchEmpty), findsWidgets,
        reason: '냉동에는 아무것도 없다');

    await tapAndWait(tester, find.text(Strings.fridgeAll).first);
    await waitFor(tester, find.text('계란'));
  });

  /// 기한 상태 칩. 같은 글자가 타일 배지에도 있으므로 칩 행 안에서만 찾는다.
  Finder statusChip(String label) => find.descendant(
        of: find.byType(ListView),
        matching: find.text(label),
      );

  testWidgets('기한 상태 필터가 등급별로 목록을 바꾼다', (tester) async {
    await enterAsGuest(tester);
    await say('계란 세 개 넣었어');
    await openFridge(tester);
    await waitFor(tester, find.text('계란'));

    // 기한을 말하지 않았으므로 기한이 지난 등급에는 아무것도 없다.
    await tapAndWait(tester, statusChip(Strings.bandShortExpired));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text(Strings.fridgeSearchEmpty), findsWidgets,
        reason: '기한 지난 재료는 없다');

    // 전체로 돌아오면 다시 보인다.
    await tapAndWait(tester, statusChip(Strings.bandShortAll));
    await waitFor(tester, find.text('계란'), reason: '전체 등급 복귀');
  });

  testWidgets('재료 상세에서 고친 수량이 저장되고 목록에 반영된다', (tester) async {
    await enterAsGuest(tester);
    await say('계란 여덟 개 넣었어');
    await openFridge(tester);
    await waitFor(tester, find.text('계란'));

    await tapAndWait(tester, find.text('계란').first,
        wait: const Duration(seconds: 3));
    await waitFor(tester, find.text(Strings.itemTitle), reason: '재료 상세');

    // 하나 늘려 9 로 만든다.
    await tapAndWait(tester, find.byIcon(Icons.add_rounded));
    await tapAndWait(tester, find.text(Strings.itemSave),
        wait: const Duration(seconds: 8));

    await waitFor(tester, fridgeScreen(), reason: '저장 후 냉장고로 돌아온다');
    await waitFor(tester, find.textContaining('9'),
        reason: '목록이 고친 수량을 보여준다');
  });

  testWidgets('화면에서 고친 것이 기록에 남고 되돌리면 복원된다', (tester) async {
    await enterAsGuest(tester);
    await say('두부 네 모 넣었어');
    await openFridge(tester);
    await waitFor(tester, find.text('두부'));

    await tapAndWait(tester, find.text('두부').first,
        wait: const Duration(seconds: 3));
    await waitFor(tester, find.text(Strings.itemTitle));
    await tapAndWait(tester, find.byIcon(Icons.remove_rounded));
    await tapAndWait(tester, find.text(Strings.itemSave),
        wait: const Duration(seconds: 8));
    await waitFor(tester, fridgeScreen());

    // 기록 탭에 수동 보정이 남아 있어야 한다.
    await tapAndWait(tester, find.text(Strings.tabHistory).last,
        wait: const Duration(seconds: 6));
    await waitFor(tester, find.text(Strings.historyAdjust),
        reason: '보정 기록');

    // 되돌리기는 **전체에서 가장 최근 줄**에만 붙는다. 그 줄은 목록 맨 끝이다.
    await scrollTo(tester, find.text(Strings.undo));
    await tapAndWait(tester, find.text(Strings.undo),
        wait: const Duration(seconds: 8));

    // 되돌린 뒤 냉장고 수량이 이전 값으로 돌아온다.
    await tapAndWait(tester, find.text(Strings.tabFridge).last,
        wait: const Duration(seconds: 6));
    await waitFor(tester, find.text('두부'));
    expect(find.textContaining('4'), findsWidgets,
        reason: '되돌리기가 이전 수량을 복원한다');
  });

  testWidgets('버린 재료는 되돌리면 되살아난다', (tester) async {
    await enterAsGuest(tester);
    await say('양파 세 개 넣었어');
    await openFridge(tester);
    await waitFor(tester, find.text('양파'));

    await tapAndWait(tester, find.text('양파').first,
        wait: const Duration(seconds: 3));
    await waitFor(tester, find.text(Strings.itemTitle));
    await tapAndWait(tester, find.text(Strings.itemDelete).first);
    // 확인 대화상자의 삭제.
    await tapAndWait(tester, find.text(Strings.itemDelete).last,
        wait: const Duration(seconds: 8));

    await waitFor(tester, fridgeScreen());
    await waitGone(tester, find.text('양파'), reason: '버린 재료는 목록에서 빠진다');

    await tapAndWait(tester, find.text(Strings.tabHistory).last,
        wait: const Duration(seconds: 6));
    await waitFor(tester, find.text(Strings.historyDiscard), reason: '폐기 기록');
    await scrollTo(tester, find.text(Strings.undo));
    await tapAndWait(tester, find.text(Strings.undo),
        wait: const Duration(seconds: 8));

    await tapAndWait(tester, find.text(Strings.tabFridge).last,
        wait: const Duration(seconds: 6));
    await waitFor(tester, find.text('양파'),
        reason: '되돌리기는 버린 묶음도 되살린다');
  });
}
