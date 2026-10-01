/// 조리 중에 호출어 없이 하는 말.
///
/// 손이 젖어 있을 때 쓰는 길이라 짧게 말한다. **짧은 말만 명령으로 본다** — 상시 듣고
/// 있으므로 옆 사람과 나누는 긴 말에 단계가 넘어가면 안 된다.
library;

/// 조리 화면이 알아듣는 말 하나.
sealed class CookCommand {
  const CookCommand();

  /// 같은 말인지 가르는 값. 한 번 말한 것을 두 번 하지 않으려고 쓴다.
  String get key;
}

final class CookNext extends CookCommand {
  const CookNext();

  @override
  String get key => 'next';
}

final class CookPrevious extends CookCommand {
  const CookPrevious();

  @override
  String get key => 'previous';
}

final class CookReadAgain extends CookCommand {
  const CookReadAgain();

  @override
  String get key => 'again';
}

final class CookTimerStart extends CookCommand {
  const CookTimerStart();

  @override
  String get key => 'timer:start';
}

final class CookTimerStop extends CookCommand {
  const CookTimerStop();

  @override
  String get key => 'timer:stop';
}

/// 말한 길이로 타이머를 건다. 단계에 시간이 적혀 있지 않아도 된다 — 사용자가 말한 시간이다.
final class CookTimerSet extends CookCommand {
  const CookTimerSet(this.length);

  final Duration length;

  @override
  String get key => 'timer:${length.inSeconds}';
}

/// 명령으로 보는 말의 최대 길이(공백 제외).
const _shortEnough = 12;

const _sino = {
  '일': 1, '이': 2, '삼': 3, '사': 4, '오': 5, '육': 6, '칠': 7, '팔': 8, '구': 9,
};

final _noise = RegExp(r'[\s,.!?~·"“”]');
final _minutes = RegExp(r'(\d+|[일이삼사오육칠팔구십]+)분');
final _seconds = RegExp(r'(\d+|[일이삼사오육칠팔구십]+)초');

/// 전사에서 조리 명령을 읽는다. 명령이 아니면 `null`.
CookCommand? readCookCommand(String transcript) {
  final said = transcript.replaceAll(_noise, '');
  if (said.isEmpty) return null;

  // 타이머는 낱말을 말해야 한다. "3분 조려요"에 타이머가 걸리면 안 된다.
  if (said.contains('타이머')) {
    final length = _lengthOf(said);
    if (length != null) return CookTimerSet(length);
    if (_has(said, const ['멈춰', '멈추', '정지', '중지', '꺼', '스톱'])) {
      return const CookTimerStop();
    }
    if (_has(said, const ['시작', '켜', '돌려', '스타트'])) {
      return const CookTimerStart();
    }
    return null;
  }

  if (said.length > _shortEnough) return null;
  if (_has(said, const ['다시', '뭐라고', '한번더'])) return const CookReadAgain();
  if (_has(said, const ['다음', '넘어가', '넘겨'])) return const CookNext();
  if (_has(said, const ['이전', '전단계', '앞단계', '뒤로'])) {
    return const CookPrevious();
  }
  return null;
}

bool _has(String said, List<String> words) => words.any(said.contains);

Duration? _lengthOf(String said) {
  final minutes = _numberOf(_minutes.firstMatch(said)?.group(1));
  final seconds = _numberOf(_seconds.firstMatch(said)?.group(1));
  if (minutes == null && seconds == null) return null;
  final length = Duration(minutes: minutes ?? 0, seconds: seconds ?? 0);
  return length > Duration.zero ? length : null;
}

/// 숫자나 한자어 수("삼", "십오", "이십")를 읽는다.
int? _numberOf(String? text) {
  if (text == null || text.isEmpty) return null;
  final digits = int.tryParse(text);
  if (digits != null) return digits;

  final ten = text.indexOf('십');
  if (ten < 0) return text.length == 1 ? _sino[text] : null;
  final tens = ten == 0 ? 1 : _sino[text.substring(0, ten)];
  final ones = ten == text.length - 1 ? 0 : _sino[text.substring(ten + 1)];
  if (tens == null || ones == null) return null;
  return tens * 10 + ones;
}
