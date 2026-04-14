import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show Clipboard;
import 'package:soliplex_agent/soliplex_agent.dart';

/// A [ClientTool] that reads text from the system clipboard.
///
/// This tool is **not** agent-gated (`requiresApproval: false`): no
/// Allow/Deny banner appears. However, reading the clipboard on the web
/// triggers a *browser* permission dialog. The `platformConsentNote`
/// callback warns the user in advance so the banner appears before the
/// OS prompt does.
///
/// On native platforms (macOS, iOS, Android, …) the read is silent —
/// `platformConsentNote` returns `null` and no notice is emitted.
///
/// Usage pattern for any tool with platform-conditional consent:
/// ```dart
/// platformConsentNote: () => kIsWeb
///     ? 'Clipboard read requires browser permission on web.'
///     : null,
/// ```
ClientTool buildGetClipboardTool() => ClientTool.simple(
      name: 'get_clipboard',
      description: 'Read the current text content of the clipboard. '
          'Returns an empty string if the clipboard holds no text.',
      executor: (toolCall, context) async {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        return data?.text ?? '';
      },
      platformConsentNote: () =>
          kIsWeb ? 'Clipboard read requires browser permission on web.' : null,
    );
