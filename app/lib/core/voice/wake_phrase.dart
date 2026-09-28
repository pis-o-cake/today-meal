/// 호출어 문구 매칭.
///
/// 온디바이스 ASR 의 전사는 띄어쓰기와 받아쓰기가 흔들린다. "헤이냉장고"·"헤이 냉장고"·
/// "해이 냉장고"가 모두 같은 호출로 처리돼야 한다.
///
/// **관대하게 잡되 아무 말에나 반응하지 않는 것**이 이 파일의 균형점이다. 너무 좁으면
/// 불러도 안 되고, 너무 넓으면 TV 소리에 깨어난다.
library;

/// 기본 호출어.
const defaultWakePhrase = '헤이 냉장고';

/// 흔히 흔들리는 표기. 전사가 이 중 하나로 나와도 호출로 본다.
const _variants = <String>[
  '헤이냉장고',
  '해이냉장고',
  '헤이냉장꼬',
  '헤이냉장구',
  '하이냉장고',
  '에이냉장고',
];

/// 비교용으로 문자열을 다듬는다. 공백과 문장부호를 없앤다.
String normalizeForWake(String raw) =>
    raw.replaceAll(RegExp(r'[\s,.!?~·]'), '');

/// 전사에 호출어가 들어 있는지.
///
/// Returns: 호출어 뒤에 이어진 말. 호출어만 말했으면 빈 문자열, 없으면 `null`.
///
/// 호출어 뒤의 말을 함께 돌려주는 이유는 "헤이 냉장고, 계란 두 개 썼어"처럼 한 번에
/// 말하는 경우를 살리기 위해서다. 그 말을 버리면 사용자가 두 번 말해야 한다.
String? matchWakePhrase(String transcript, {String phrase = defaultWakePhrase}) {
  final haystack = normalizeForWake(transcript);
  if (haystack.isEmpty) return null;

  final candidates = <String>[normalizeForWake(phrase), ..._variants];
  for (final candidate in candidates) {
    final index = haystack.indexOf(candidate);
    if (index < 0) continue;
    return haystack.substring(index + candidate.length);
  }
  return null;
}
