import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/design/breakpoints.dart';
import '../../core/design/responsive.dart';
import '../../core/design/tokens.dart';
import '../../core/di.dart';
import '../../core/l10n/strings.dart';
import '../../core/network/api_client.dart';

/// 서버 왕복을 확인하는 자리표시 화면.
///
/// S-00 의 앱 절반이다. **실제 화면은 목업이 확정된 뒤 만든다** — 지금 화면을 지어두면
/// 목업과 어긋난 것을 다시 뜯게 된다.
///
/// 이 화면이 증명하는 것은 셋이다. 설정을 읽는가, 서버에 닿는가, 반응형 기제가 도는가.
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  _Probe _probe = const _Probe.checking();

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final config = di<AppConfig>();
    if (!config.hasServer) {
      setState(() => _probe = const _Probe.failed(Strings.serverMissing));
      return;
    }
    setState(() => _probe = const _Probe.checking());
    try {
      final body = await di<ApiClient>().health();
      if (!mounted) return;
      setState(() => _probe = _Probe.connected(body));
    } catch (error) {
      if (!mounted) return;
      // 실패를 성공처럼 보이게 두지 않는다. 원인을 화면에 남긴다.
      setState(() => _probe = _Probe.failed('${Strings.serverFailed}\n$error'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = context.formFactor;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentFrame(
            child: ResponsiveTwoPane(
              primary: _Section(
                title: Strings.appName,
                child: _ProbeView(probe: _probe, onRetry: _check),
              ),
              secondary: _Section(
                title: Strings.wakeWordHint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Strings.uiPending,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: Tokens.gapTight),
                    // 반응형 기제가 실제로 갈리는지 눈으로 확인할 수 있게 남긴다.
                    Text(
                      '${form.name} · ${form.columns}단',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.gapCard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Tokens.gapCard),
            child,
          ],
        ),
      ),
    );
  }
}

class _ProbeView extends StatelessWidget {
  const _ProbeView({required this.probe, required this.onRetry});

  final _Probe probe;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (probe) {
      _Checking() => Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: Tokens.gapTight),
            Text(Strings.serverChecking, style: theme.textTheme.bodyLarge),
          ],
        ),
      _Connected(:final body) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Strings.serverConnected, style: theme.textTheme.bodyLarge),
            const SizedBox(height: Tokens.gapTight),
            // 가짜 모델로 돌고 있으면 드러나야 한다. 조용히 가짜를 쓰면 품질을
            // 측정했다고 착각한다.
            Text(
              'model ${body['model']} · prompt ${body['prompt_version']}'
              '${body['llm_fake'] == true ? ' · FAKE' : ''}',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      _Failed(:final message) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.error),
            ),
            const SizedBox(height: Tokens.gapTight),
            TextButton(onPressed: onRetry, child: const Text(Strings.retry)),
          ],
        ),
    };
  }
}

sealed class _Probe {
  const _Probe();

  const factory _Probe.checking() = _Checking;
  const factory _Probe.connected(Map<String, dynamic> body) = _Connected;
  const factory _Probe.failed(String message) = _Failed;
}

final class _Checking extends _Probe {
  const _Checking();
}

final class _Connected extends _Probe {
  const _Connected(this.body);

  final Map<String, dynamic> body;
}

final class _Failed extends _Probe {
  const _Failed(this.message);

  final String message;
}
