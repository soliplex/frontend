import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:soliplex_agent/soliplex_agent.dart';

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
