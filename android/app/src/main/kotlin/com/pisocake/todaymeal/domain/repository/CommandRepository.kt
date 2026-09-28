package com.pisocake.todaymeal.domain.repository

import com.pisocake.todaymeal.domain.model.ChangeRecord

/**
 * 음성 명령 전송과 되돌리기.
 *
 * <p>명령 ID 는 <b>앱이 발화마다 만들어</b> 보낸다. 서버가 만들면 네트워크 재시도를 구분할 수
 * 없어 재고가 두 번 바뀐다.
 */
interface CommandRepository {

    /**
     * 전사된 발화를 서버로 보낸다.
     *
     * @param commandId 발화마다 새로 만드는 멱등 키. 재시도할 때는 같은 값을 보낸다.
     * @param utterance 전사 원문.
     */
    suspend fun interpret(commandId: String, utterance: String): Result<CommandOutcome>

    /** 명령 묶음 전체를 되돌린다. */
    suspend fun undo(commandId: String): Result<CommandOutcome>

    /** 변경 이력을 읽는다. */
    suspend fun history(): Result<List<ChangeRecord>>
}

/**
 * 서버가 판정한 결과.
 *
 * @property spoken 읽어줄 한 문장. 상세는 화면에 남긴다.
 * @property clarificationQuestion 되물을 한 가지. 있으면 아직 반영되지 않았다.
 * @property undoToken 되돌리기 대상 명령.
 */
data class CommandOutcome(
    val commandId: String,
    val status: String,
    val intent: String,
    val spoken: String?,
    val clarificationQuestion: String? = null,
    val undoToken: String? = null,
)
