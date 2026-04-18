import 'package:flutter/services.dart' show Clipboard;
import 'package:soliplex_agent/soliplex_agent.dart';

ClientTool buildGetClipboardTool() => ClientTool.simple(
      name: 'get_clipboard',
      description: 'Read the current text content of the clipboard. '
          'Returns an empty string if the clipboard holds no text.',
      executor: (toolCall, context) async {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        return data?.text ?? '';
      },
    );
