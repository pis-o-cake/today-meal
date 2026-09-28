import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/voice/voice_ports.dart';
import '../../core/voice/voice_session_manager.dart';
import '../../core/voice/voice_state.dart';
import '../../domain/repository/repositories.dart';

/// 대화 오버레이의 상태.
///
/// 음성 계층을 직접 다루지 않는다. [VoiceSessionManager] 의 상태를 읽고 서버 호출을
/// 넘겨주기만 한다.
class ConversationViewModel extends ChangeNotifier {
  ConversationViewModel({
    required VoiceSessionManager voice,
    required CommandRepository command,
    required String retryMessage,
  })  : _voice = voice,
        _command = command,
        _retryMessage = retryMessage {
    _subscribe();
  }

  static const _uuid = Uuid();

  final VoiceSessionManager _voice;
  final CommandRepository _command;
  final String _retryMessage;

  VoiceState _state = const Suspended();
  CommandOutcome? _lastOutcome;
  String? _lastUtterance;

  VoiceState get state => _state;
  CommandOutcome? get lastOutcome => _lastOutcome;
  String? get lastUtterance => _lastUtterance;

  /// 되돌릴 것이 있는지. 조회에는 되돌릴 것이 없다.
  bool get canUndo => _lastOutcome?.undoToken != null;

  void _subscribe() {
    // 호출어 감지를 세션 시작으로 잇는다. 감지기는 세션 매니저가 다룬다.
    _voice.bindWakeWord(_handle);
    _voice.states.listen((next) {
      _state = next;
      if (next is Listening && next.partialText != null) {
        _lastUtterance = next.partialText;
      }
      if (next is Processing) _lastUtterance = next.utterance;
      notifyListeners();
    });
  }

  /// 마이크 버튼. 웨이크워드가 전경 한정이라 보조 경로를 상시 유지한다.
  Future<void> onMicButton() => _voice.startSession(_handle);

  /// 전사된 발화를 서버로 보낸다.
  ///
  /// **`commandId` 를 발화마다 한 번만 만든다.** 재시도에서 새로 만들면 서버가 중복을
  /// 막을 수 없다.
  Future<VoiceTurnResult> _handle(String utterance) async {
    final commandId = _uuid.v4();
    try {
      final outcome = await _command.interpret(
        commandId: commandId,
        utterance: utterance,
      );
      _lastOutcome = outcome;
      notifyListeners();

      final question = outcome.clarificationQuestion;
      if (question != null) return TurnNeedsClarification(question);
      return TurnAnswered(outcome.spoken ?? '');
    } catch (error) {
      // 실패를 완료처럼 알리지 않는다.
      return TurnFailed(spoken: _retryMessage, logDetail: '$error');
    }
  }

  /// 직전 변경 묶음을 되돌린다.
  Future<void> undo() async {
    final token = _lastOutcome?.undoToken;
    if (token == null) return;
    try {
      _lastOutcome = await _command.undo(token);
    } catch (error) {
      debugPrint('undo failed: $error');
    }
    notifyListeners();
  }

  /// 전경 복귀. 웨이크워드가 전경 한정이라 이 호출이 감지를 켠다.
  Future<void> resume() => _voice.onForeground();

  /// 배경 전환. 감지를 멈추고 그 사실을 표시한다.
  Future<void> suspend() => _voice.onBackground();

  Future<void> toggleMute() async {
    if (_state is Muted) {
      await _voice.unmute();
    } else {
      await _voice.mute();
    }
  }
}
