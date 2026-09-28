import 'package:flutter_test/flutter_test.dart';
import 'package:today_meal/core/design/labels.dart';
import 'package:today_meal/domain/model/inventory.dart';

/// 도메인 값이 화면 문구로 바뀌는 지점.
///
/// 서버가 준 값을 그대로 내보내면 "계란 10.000개" 가 되고 "2mo" 가 된다. 실기기에서
/// 실제로 그렇게 나왔다.
void main() {
  group('number', () {
    test('NUMERIC 의 꼬리 0 을 지운다', () {
      expect(Labels.number('10.000'), '10');
      expect(Labels.number('2.00'), '2');
    });

    test('의미 있는 소수부는 남긴다', () {
      expect(Labels.number('0.5'), '0.5');
      expect(Labels.number('1.50'), '1.5');
    });

    test('정수는 건드리지 않는다', () {
      expect(Labels.number('10'), '10');
    });
  });

  group('unit', () {
    test('정규화된 기호를 한국어 표기로 바꾼다', () {
      expect(Labels.unit('ea'), '개');
      expect(Labels.unit('mo'), '모');
      expect(Labels.unit('bunch'), '단');
    });

    test('모르는 기호는 그대로 쓴다', () {
      // 감추면 값이 사라진 것처럼 보인다.
      expect(Labels.unit('slab'), 'slab');
    });

    test('단위가 없으면 빈 문자열', () {
      expect(Labels.unit(null), '');
    });
  });

  group('amount', () {
    test('확정 수량은 숫자와 단위를 붙인다', () {
      const batch = IngredientBatch(
        batchId: 1,
        ingredientId: 1,
        name: '계란',
        quantity: '10.000',
        unit: 'ea',
        certainty: QuantityCertainty.exact,
        storage: StorageLocation.fridge,
        freshness: Freshness.unknown,
      );
      expect(Labels.amount(batch), '10개');
    });

    test('잔량을 모르면 숫자를 만들지 않는다', () {
      const batch = IngredientBatch(
        batchId: 2,
        ingredientId: 2,
        name: '김치',
        qualitativeAmount: '조금',
        certainty: QuantityCertainty.qualitative,
        storage: StorageLocation.fridge,
        freshness: Freshness.unknown,
        quantityUncertain: true,
      );
      expect(Labels.amount(batch), '조금');
    });
  });
}
