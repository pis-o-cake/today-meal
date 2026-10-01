/// 호출어 문구 매칭.
///
/// 인식 서비스의 전사는 띄어쓰기와 받아쓰기가 흔들린다. "헤이 키친"·"헤이키친"·"해이 키친"이
/// 모두 같은 호출로 처리돼야 한다.
///
/// 제품 호출어는 화면이 말하는 **"헤이 키친"**이다. 한때 인식률 때문에 "자비스"를 기본으로
/// 뒀지만, 화면이 말하는 문구로 깨어나지 않는 것은 사용자에게 고장이다.
///
/// **표기 목록이 아니라 소리로 비교한다.** 실기기(SM-E426S)에서 "헤이 키친"을 여섯 번
/// 불렀을 때 전사는 `헤이키친` 두 번, `베이키친`·`에이키친`·`hat kitchen` 한 번씩이었다.
/// 첫 낱말은 무엇으로 받아써질지 알 수 없어서 목록으로는 따라갈 수 없다.
///
/// 넓게 잡아도 되는 근거는 호출어가 **두 낱말 한 벌**이라는 점이다. "헤이"처럼 들리는
/// 말 바로 뒤에 "키친"처럼 들리는 말이 붙어야 하며, 한쪽만으로는 깨어나지 않는다.
///
/// CAUTION: 시연에서 불러도 안 깨는 것을 막으려고 오인식 쪽으로 기울였다. 주방에 상시
/// 켜두는 제품에서는 TV·대화 소리에 깨어날 수 있으므로 범위를 다시 좁혀야 한다.
library;

/// 기본 호출어. 화면 표시 문구와 같아야 한다.
const defaultWakePhrase = '헤이 키친';

/// 이전 호출어. 익숙해진 사용자를 끊지 않는다.
const _legacy = <String>[
  '자비스',
  '자비쓰',
  '재비스',
  '자피스',
  '차비스',
  '쟈비스',
  '자비수',
  'jarvis',
  '헤이냉장고',
  '해이냉장고',
];

/// 로마자로 받아써진 "키친". 인식기가 이 낱말에서만 영어로 넘어간다.
final _kitchenWord = RegExp('kitchens?|kitchin|kitchn|kichen|kichin|chicken|kitten|keychain');

/// 로마자로 받아써진 "헤이". 바로 뒤에 "키친"이 붙는 자리에서만 본다.
final _heyWord = RegExp(r'(hey|hay|hei|hae|hai|hat|had|hate|head|heck|he|hi|eh|ay|a|k)$');

final _latinOnly = RegExp(r'^[a-z]+$');

/// "키친타월"은 호출이 아니다. 뒤에 이 말이 붙으면 건너뛴다.
final _towel = RegExp('타월|타올|towel');

/// 발화 맨 앞에서 "헤이"로 봐주는 토막의 최대 길이.
///
/// 첫 낱말은 짧고 약하게 발음돼 엉뚱한 글자로 받아써진다. 맨 앞의 짧은 토막은 무엇이든
/// 첫 낱말로 본다.
const _garbledHangul = 2;
const _garbledLatin = 6;

const _initials = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
const _vowels = 'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ';

/// 받침. 첫 칸의 공백은 받침 없음이다.
const _finals = ' ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ';

const _open = ' ';

/// 한글 한 글자의 첫소리·가운뎃소리·받침.
typedef _Sound = ({String first, String vowel, String last});

/// 한글 음절이 아니면 `null`.
_Sound? _soundOf(String text, int at) {
  if (at < 0 || at >= text.length) return null;
  final code = text.codeUnitAt(at) - 0xAC00;
  if (code < 0 || code >= 11172) return null;
  return (
    first: _initials[code ~/ 588],
    vowel: _vowels[(code % 588) ~/ 28],
    last: _finals[code % 28],
  );
}

/// 비교용으로 문자열을 다듬는다. 공백과 문장부호를 없애고 로마자는 소문자로 맞춘다.
String normalizeForWake(String raw) =>
    raw.replaceAll(RegExp(r'[\s,.!?~·]'), '').toLowerCase();

/// 전사에 호출어가 들어 있는지.
///
/// Returns: 호출어 뒤에 이어진 말. 호출어만 말했으면 빈 문자열, 없으면 `null`.
///
/// 호출어 뒤의 말을 함께 돌려주는 이유는 "헤이 키친, 계란 두 개 썼어"처럼 한 번에
/// 말하는 경우를 살리기 위해서다. 그 말을 버리면 사용자가 두 번 말해야 한다.
String? matchWakePhrase(String transcript, {String phrase = defaultWakePhrase}) {
  final heard = normalizeForWake(transcript);
  if (heard.isEmpty) return null;

  for (final exact in [normalizeForWake(phrase), ..._legacy]) {
    final index = heard.indexOf(exact);
    if (index >= 0) return heard.substring(index + exact.length);
  }
  return _afterHeyKitchen(heard);
}

/// "헤이"처럼 들리는 말 바로 뒤에 "키친"처럼 들리는 말이 붙은 자리를 찾는다.
///
/// 맨 앞에서 시작하는 "키친"은 보지 않는다 — 첫 낱말이 없으면 한 벌이 아니다.
String? _afterHeyKitchen(String heard) {
  for (var at = 1; at < heard.length; at++) {
    final length = _kitchenLength(heard, at);
    if (length == 0) continue;

    final end = at + length;
    if (_towel.matchAsPrefix(heard, end) != null) continue;
    if (!_soundsLikeHey(heard.substring(0, at))) continue;
    return heard.substring(end);
  }
  return null;
}

/// [at] 에서 시작하는 "키친" 비슷한 말의 길이. 없으면 0.
int _kitchenLength(String heard, int at) {
  final word = _kitchenWord.matchAsPrefix(heard, at);
  if (word != null) return word.end - at;

  final ki = _soundOf(heard, at);
  final chin = _soundOf(heard, at + 1);
  if (ki == null || chin == null) return 0;

  // 모음은 좁게 둔다. 넓히면 "기전"·"개선" 같은 흔한 낱말이 걸린다.
  const narrow = 'ㅣㅟㅢ';
  final kiLike = 'ㅋㄱㄲㅌㅊㅍ'.contains(ki.first) &&
      narrow.contains(ki.vowel) &&
      ' ㅅㅆㄷㅌㄱ'.contains(ki.last);
  if (!kiLike) return 0;

  // "치킨"처럼 두 첫소리가 뒤바뀐 전사도 받는다 — 더 흔한 낱말이라 인식기가 그쪽으로 끌린다.
  final chinLike = 'ㅊㅈㅉㅅㅆㅌㅋ'.contains(chin.first) &&
      narrow.contains(chin.vowel) &&
      'ㄴㅇㅁ'.contains(chin.last);
  // 받침이 떨어진 전사는 "키치"만 받는다. 첫소리까지 풀면 "기지"·"피시"가 걸린다.
  final dropped = chin.first == 'ㅊ' && narrow.contains(chin.vowel) && chin.last == _open;
  return chinLike || dropped ? 2 : 0;
}

/// "키친" 바로 앞의 말이 "헤이"처럼 들리는지.
bool _soundsLikeHey(String before) {
  if (before.length <= _garbledHangul) return true;
  if (before.length <= _garbledLatin && _latinOnly.hasMatch(before)) return true;
  if (_heyWord.hasMatch(before)) return true;

  final last = _soundOf(before, before.length - 1);
  if (last == null) return false;

  // "헤"·"해"·"햇"처럼 한 글자로 줄어든 경우.
  if ('ㅔㅐㅖㅒㅚㅙㅞ'.contains(last.vowel)) return true;

  // "헤이"·"베이"·"하이"처럼 "이"로 끝나는 두 글자.
  final glide = 'ㅇㅎ'.contains(last.first) && 'ㅣㅢ'.contains(last.vowel) && last.last == _open;
  if (!glide) return false;
  final lead = _soundOf(before, before.length - 2);
  return lead != null && 'ㅔㅐㅖㅒㅚㅙㅞㅏㅑㅓㅕ'.contains(lead.vowel);
}
