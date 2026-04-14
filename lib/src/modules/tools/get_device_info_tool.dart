import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:soliplex_agent/soliplex_agent.dart';

/// A [ClientTool] that reports basic platform information.
///
/// Ungated — no agent approval (`requiresApproval: false`) and no
/// platform consent dialog. The tool reads only publicly available
/// runtime facts; there is nothing sensitive to gate.
///
/// Example response:
/// ```json
/// {"platform": "macOS", "isWeb": false}
/// ```
ClientTool buildGetDeviceInfoTool() => ClientTool.simple(
      name: 'get_device_info',
      description: 'Returns basic information about the current device '
          'and platform (OS name, web flag).',
      executor: (toolCall, context) async {
        final info = <String, Object>{
          'platform': defaultTargetPlatform.name,
          'isWeb': kIsWeb,
        };
        return jsonEncode(info);
      },
    );
