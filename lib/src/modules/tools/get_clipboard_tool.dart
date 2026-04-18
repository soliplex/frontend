import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show Clipboard;
import 'package:soliplex_agent/soliplex_agent.dart';

ClientTool buildGetClipboardTool() => ClientTool.simple(
      name: 'get_clipboard',
      description: 'Read the current text content of the clipboard. '
          'Returns an empty string if the clipboard holds no text.',
      executor: (toolCall, context) async {
        // Browser has its own OS permission dialog; native has none.
        if (!kIsWeb) {
          final approval = await context.requestApproval(
            toolCallId: toolCall.id,
            toolName: 'get_clipboard',
            arguments: const {},
            rationale: 'Read clipboard contents',
          );
          switch (approval) {
            case AllowOnce() || AllowSession():
              break;
            case Deny():
              return 'Error: clipboard access denied by user';
          }
        }
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        return data?.text ?? '';
      },
    );
