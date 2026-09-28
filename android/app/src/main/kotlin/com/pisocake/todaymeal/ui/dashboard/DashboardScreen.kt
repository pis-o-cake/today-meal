package com.pisocake.todaymeal.ui.dashboard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.pisocake.todaymeal.R
import com.pisocake.todaymeal.core.design.TodayMealSpacing
import com.pisocake.todaymeal.core.design.TodayMealTheme
import com.pisocake.todaymeal.core.voice.VoiceState
import com.pisocake.todaymeal.domain.model.IngredientBatch
import com.pisocake.todaymeal.domain.model.MenuSuggestion

/**
 * 대기 대시보드.
 *
 * <p>주방에 들어오면 보이는 화면이다. 재고 입력 폼보다 **오늘 가능한 메뉴와 먼저 쓸 재료**를
 * 앞세운다. 정상 흐름은 화면 조작 없이 완료되어야 하므로 버튼은 보조 경로다.
 */
@Composable
fun DashboardRoute(
    onOpenFridge: () -> Unit,
    viewModel: DashboardViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    DashboardScreen(
        state = state,
        onUndo = viewModel::undoLastChange,
        onToggleMute = viewModel::toggleMute,
        onOpenFridge = onOpenFridge,
    )
}

@Composable
fun DashboardScreen(
    state: DashboardUiState,
    onUndo: () -> Unit,
    onToggleMute: () -> Unit,
    onOpenFridge: () -> Unit,
) {
    Scaffold { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(TodayMealSpacing.gutter),
            verticalArrangement = Arrangement.spacedBy(TodayMealSpacing.card),
        ) {
            StatusBar(state = state, onToggleMute = onToggleMute)

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(TodayMealSpacing.card),
            ) {
                MenuColumn(state = state, modifier = Modifier.weight(1.4f))
                PriorityColumn(
                    state = state,
                    onOpenFridge = onOpenFridge,
                    modifier = Modifier.weight(1f),
                )
            }

            Spacer()
            WakeWordHint()
            RecentChange(state = state, onUndo = onUndo)
        }
    }
}

@Composable
private fun StatusBar(state: DashboardUiState, onToggleMute: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = stringResource(R.string.app_name),
            style = MaterialTheme.typography.titleLarge,
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            // 색만으로 상태를 구분하지 않고 문구를 함께 쓴다.
            Text(
                text = stringResource(state.voiceState.labelRes()),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            TextButton(onClick = onToggleMute) {
                val label = if (state.voiceState is VoiceState.Muted) {
                    R.string.action_unmute
                } else {
                    R.string.action_mute
                }
                Text(stringResource(label))
            }
        }
    }
}

@Composable
private fun MenuColumn(state: DashboardUiState, modifier: Modifier = Modifier) {
    Card(modifier = modifier) {
        Column(Modifier.padding(TodayMealSpacing.card)) {
            Text(
                text = stringResource(R.string.dashboard_menu_title),
                style = MaterialTheme.typography.titleLarge,
            )
            if (!state.hasMenus) {
                Text(
                    text = stringResource(R.string.dashboard_empty_menu),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = TodayMealSpacing.tight),
                )
                return@Column
            }
            LazyColumn(verticalArrangement = Arrangement.spacedBy(TodayMealSpacing.tight)) {
                items(state.menus, key = MenuSuggestion::suggestionId) { menu ->
                    Text(text = menu.name, style = MaterialTheme.typography.headlineMedium)
                }
            }
        }
    }
}

@Composable
private fun PriorityColumn(
    state: DashboardUiState,
    onOpenFridge: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(modifier = modifier) {
        Column(Modifier.padding(TodayMealSpacing.card)) {
            Text(
                text = stringResource(R.string.dashboard_priority_title),
                style = MaterialTheme.typography.titleLarge,
            )
            if (!state.hasPriority) {
                Text(
                    text = stringResource(R.string.dashboard_empty_priority),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = TodayMealSpacing.tight),
                )
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(TodayMealSpacing.tight)) {
                    items(state.priorityBatches, key = IngredientBatch::batchId) { batch ->
                        Text(text = batch.displayName, style = MaterialTheme.typography.bodyLarge)
                    }
                }
            }
            TextButton(onClick = onOpenFridge) {
                Text(stringResource(R.string.dashboard_open_fridge))
            }
        }
    }
}

@Composable
private fun WakeWordHint() {
    Text(
        text = stringResource(R.string.voice_wake_word_hint),
        style = MaterialTheme.typography.bodyLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun RecentChange(state: DashboardUiState, onUndo: () -> Unit) {
    val summary = state.lastChangeSummary ?: return
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = "${stringResource(R.string.dashboard_recent_change)}: $summary",
            style = MaterialTheme.typography.bodyMedium,
        )
        if (state.canUndo) {
            TextButton(onClick = onUndo) { Text(stringResource(R.string.action_undo)) }
        }
    }
}

@Composable
private fun Spacer() {
    Box(Modifier.fillMaxWidth())
}

/** 음성 상태를 문구 리소스로 옮긴다. Compose 에 한국어를 직접 적지 않는다. */
private fun VoiceState.labelRes(): Int = when (this) {
    VoiceState.Waiting -> R.string.voice_state_waiting
    is VoiceState.Listening -> R.string.voice_state_listening
    is VoiceState.Processing -> R.string.voice_state_processing
    is VoiceState.Clarifying -> R.string.voice_state_clarifying
    is VoiceState.Speaking -> R.string.voice_state_speaking
    VoiceState.Muted -> R.string.voice_state_muted
    is VoiceState.Unavailable -> R.string.voice_state_unavailable
}

@Preview(widthDp = 1280, heightDp = 800)
@Composable
private fun DashboardPreview() {
    TodayMealTheme {
        DashboardScreen(
            state = DashboardUiState(lastChangeSummary = "계란 2개 사용 → 8개 남음", undoToken = "x"),
            onUndo = {},
            onToggleMute = {},
            onOpenFridge = {},
        )
    }
}
