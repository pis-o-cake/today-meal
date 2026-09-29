/// 변경 이력 한 줄.
///
/// 수량 변경과 상태 변경을 같은 타임라인에 섞는다. 상태 변경은 잔량 칸이 비어 있어
/// **개봉과 이동이 수량을 바꾸지 않는다는 사실**이 화면에 드러난다.
class ChangeRecord {
  const ChangeRecord({
    required this.kind,
    required this.action,
    required this.name,
    required this.batchId,
    required this.occurredAt,
    this.quantityBefore,
    this.quantityAfter,
    this.unit,
    this.isEstimated = false,
    this.commandId,
    this.reversesEventId,
    this.utterance,
    this.spokenResponse,
  });

  final HistoryKind kind;

  /// 변경 동작 또는 상태 종류.
  final String action;

  final String name;
  final int batchId;
  final String? quantityBefore;
  final String? quantityAfter;
  final String? unit;

  /// 추정값인지. 사용자가 말한 숫자와 앱이 추정한 숫자는 다른 사실이다.
  final bool isEstimated;

  final DateTime occurredAt;
  final String? commandId;

  /// 되돌린 대상. 있으면 역산 이벤트다.
  final int? reversesEventId;

  /// 이 변경을 일으킨 발화 원문.
  ///
  /// 기록 화면이 "말한 문장 → 바뀐 결과" 로 보여주는 근거다. 없으면 말풍선을 그리지
  /// 않는다 — 문장을 지어내지 않는다.
  final String? utterance;

  /// 그때 읽어준 응답.
  final String? spokenResponse;

  bool get changesQuantity => quantityAfter != null;
}

enum HistoryKind {
  quantity,
  state;

  static HistoryKind parse(String? raw) =>
      raw == 'state' ? HistoryKind.state : HistoryKind.quantity;
}
