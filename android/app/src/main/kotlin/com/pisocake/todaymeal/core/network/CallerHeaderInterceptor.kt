package com.pisocake.todaymeal.core.network

import okhttp3.Interceptor
import okhttp3.Response

/**
 * 호출자 식별 헤더를 붙인다.
 *
 * <p>CAUTION: <b>보안 기능이 아니다.</b> 서버는 이 값을 검증하지 않는다 — 서명도 만료도 세션도
 * 없다. 간편 로그인은 사용자를 구분하기만 하며, 헤더가 없으면 서버가 기본 가구로 처리해 로그인
 * 없이도 전 기능이 동작한다. 근거는 `docs/design/0001-mvp-technical-design.md` 에 있다.
 */
class CallerHeaderInterceptor(
    private val userIdProvider: () -> Long? = { null },
    private val householdIdProvider: () -> Long? = { null },
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val builder = chain.request().newBuilder()
        userIdProvider()?.let { builder.header(HEADER_USER_ID, it.toString()) }
        householdIdProvider()?.let { builder.header(HEADER_HOUSEHOLD_ID, it.toString()) }
        return chain.proceed(builder.build())
    }

    private companion object {
        const val HEADER_USER_ID = "X-User-Id"
        const val HEADER_HOUSEHOLD_ID = "X-Household-Id"
    }
}
