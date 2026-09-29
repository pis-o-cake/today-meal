import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:today_meal/ui/widgets/brand_marks.dart';

void main() {
  testWidgets('로고가 상자 안에서 그려진다', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [GoogleMark(size: 48), KakaoMark(size: 48)],
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
