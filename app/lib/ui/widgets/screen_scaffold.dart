/// 목록 화면의 뼈대.
///
/// 냉장고·기록·마이페이지가 같은 배경과 머리말 여백을 쓴다. 화면마다 다시 짜면 여백과
/// 배경이 조금씩 어긋난다.
///
/// **오늘 화면은 이것을 쓰지 않는다.** 오늘은 등급 색을 화면 전체에 입히고 머리말도
/// 가운데 정렬이라 구조가 다르다.
library;

import 'package:flutter/material.dart';

import '../../core/design/skin.dart';

/// 배경 + 고정 머리말 + 본문.
///
/// 머리말 생김새는 화면마다 달라 통째로 받는다 — 제목 자리를 억지로 공통화하면
/// 캐릭터와 검색 버튼을 넣은 냉장고 머리말이 들어가지 않는다.
///
/// IMPORTANT: 투명한 [Scaffold] 를 안에 둔다. 잉크 효과(`InkWell`)는 `Material` 조상을
/// 요구하며, 셸이 감싸 줄 것을 기대하면 이 화면을 따로 띄울 때 터진다 — 실기기에서 겪은
/// 결함이다. 배경은 [Skin.listBackground] 가 그리므로 투명이어야 한다.
class ListScreen extends StatelessWidget {
  const ListScreen({required this.header, required this.child, super.key});

  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(gradient: context.skin.listBackground),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: header,
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      );
}

/// 목록 아래를 덮는 그라데이션.
///
/// 하단 탭이 본문 위에 얹히므로, 마지막 항목이 탭 밑으로 **사라지는 것처럼** 보여야
/// 한다. 이것이 없으면 글자가 탭 테두리에서 잘린 것으로 읽힌다.
class ListFade extends StatelessWidget {
  const ListFade({super.key});

  @override
  Widget build(BuildContext context) {
    final edge = context.skin.neutral.bgEdge;
    return IgnorePointer(
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              edge.withValues(alpha: 0),
              edge.withValues(alpha: 0.92),
            ],
          ),
        ),
      ),
    );
  }
}

/// 목록 화면의 머리말 버튼. 검색처럼 한 가지 행동에 쓴다.
class HeaderButton extends StatelessWidget {
  const HeaderButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;

  /// 스크린리더 이름. 아이콘만 있는 버튼이라 반드시 둔다.
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: onPressed,
        iconSize: 20,
        color: skin.inkMuted,
        tooltip: label,
        style: IconButton.styleFrom(
          backgroundColor: skin.glass,
          shape: CircleBorder(side: BorderSide(color: skin.edge)),
        ),
        icon: Icon(icon),
      ),
    );
  }
}
