/// 한국어 조사 선택.
///
/// 앞말의 받침에 따라 조사가 달라진다. "이메일(으)로" 처럼 괄호로 피하면 읽기 나쁘고,
/// 하나로 고정하면 절반이 틀린다.
///
/// 받침 판정은 한글 음절의 코드 구조로 한다 — `(코드 - 0xAC00) % 28` 이 종성 번호이며
/// 0 이면 받침이 없다. 한글이 아닌 글자로 끝나면 받침이 없는 것으로 다룬다.
library;

abstract final class Particles {
  static const _base = 0xAC00;
  static const _last = 0xD7A3;

  /// 종성 번호. 받침이 없으면 0, ㄹ 이면 8 이다.
  static int? _finalConsonant(String word) {
    if (word.isEmpty) return null;
    final code = word.runes.last;
    if (code < _base || code > _last) return null;
    return (code - _base) % 28;
  }

  /// `로` / `으로`.
  ///
  /// 받침이 없거나 ㄹ 받침이면 `로` 다 — "이메일로", "카카오로", "구글로".
  static String ro(String word) {
    final coda = _finalConsonant(word);
    if (coda == null || coda == 0 || coda == 8) return '로';
    return '으로';
  }

  /// `은` / `는`.
  static String neun(String word) {
    final coda = _finalConsonant(word);
    return (coda == null || coda == 0) ? '는' : '은';
  }

  /// `을` / `를`.
  static String reul(String word) {
    final coda = _finalConsonant(word);
    return (coda == null || coda == 0) ? '를' : '을';
  }

  /// `이` / `가`.
  static String i(String word) {
    final coda = _finalConsonant(word);
    return (coda == null || coda == 0) ? '가' : '이';
  }
}
