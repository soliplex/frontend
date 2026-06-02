import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'effective_marking.dart';

/// Configurable copy for the pre-access notice. A flavor can override
/// [markingNoticeConfigProvider] to supply agency- or DoD-required language.
@immutable
class MarkingNoticeConfig {
  const MarkingNoticeConfig({
    required this.title,
    required this.body,
    required this.acknowledgeLabel,
  });

  final String title;
  final String body;
  final String acknowledgeLabel;

  /// Default US Government information-system consent language.
  static const MarkingNoticeConfig standard = MarkingNoticeConfig(
    title: 'Authorized Use Notice',
    body: 'You are accessing a U.S. Government (USG) Information System (IS) '
        'that is provided for USG-authorized use only. By using this IS you '
        'consent to the following conditions:\n\n'
        '• The USG routinely intercepts and monitors communications on this '
        'IS for purposes including, but not limited to, penetration testing, '
        'monitoring, network operations and defense, and counterintelligence '
        'investigations.\n'
        '• At any time, the USG may inspect and seize data stored on this IS.\n'
        '• This IS includes security measures to protect USG interests — not '
        'for your personal benefit or privacy.\n\n'
        'Content within this application may carry classification or control '
        'markings. Handle all information in accordance with its marking and '
        'applicable handling instructions.',
    acknowledgeLabel: 'I ACKNOWLEDGE',
  );
}

/// The active pre-access notice copy. Override in a flavor to localise.
final markingNoticeConfigProvider = Provider<MarkingNoticeConfig>(
  (ref) => MarkingNoticeConfig.standard,
);

/// Whether the user has acknowledged the pre-access notice this session.
///
/// A signal (the app's reactive-state primitive) exposed via Riverpod for
/// DI/overrides. In-memory and reset every launch by design: the notice
/// must be acknowledged before any protected content is shown.
final markingNoticeAcknowledgedProvider = Provider<Signal<bool>>(
  (ref) => Signal<bool>(false),
);

/// Full-screen pre-access notice. Shows the effective marking banner first
/// (so screen readers announce it before the notice), the consent copy, and
/// a single explicit acknowledgment action. No protected content is rendered
/// behind it.
class PreAccessNotice extends ConsumerWidget {
  const PreAccessNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marking = ref.watch(effectiveMarkingProvider);
    final config = ref.watch(markingNoticeConfigProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: SoliplexMarkingBanner(marking: marking),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: SoliplexBreakpoints.desktop,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(SoliplexSpacing.s6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(config.title, style: textTheme.headlineMedium),
                      const SizedBox(height: SoliplexSpacing.s4),
                      Text(config.body, style: textTheme.bodyMedium),
                      const SizedBox(height: SoliplexSpacing.s6),
                      SoliplexButton.filled(
                        onPressed: () => ref
                            .read(markingNoticeAcknowledgedProvider)
                            .value = true,
                        child: Text(config.acknowledgeLabel),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
