import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/http_category.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/http_event_group.dart';

import '../../../helpers/http_event_factories.dart';

HttpEventGroup _groupFor(String url) => HttpEventGroup(
      requestId: 'req-1',
      request: createRequestEvent(uri: Uri.parse(url)),
    );

void main() {
  group('categoryOf', () {
    test('AG-UI traffic is LLM', () {
      expect(
        categoryOf(_groupFor('http://localhost/api/v1/rooms/r1/agui')),
        HttpCategory.llm,
      );
      expect(
        categoryOf(
          _groupFor('http://localhost/api/v1/rooms/r1/agui/t1/run-1'),
        ),
        HttpCategory.llm,
      );
    });

    test('identity endpoints are Auth', () {
      expect(
        categoryOf(_groupFor('http://localhost/api/user_info')),
        HttpCategory.auth,
      );
      expect(
        categoryOf(
          _groupFor('https://idp.example.com/.well-known/openid-configuration'),
        ),
        HttpCategory.auth,
      );
    });

    test('other backend endpoints are System', () {
      for (final path in const [
        'http://localhost/api/v1/rooms',
        'http://localhost/api/v1/rooms/r1/documents',
        'http://localhost/api/v1/rooms/r1/mcp_token',
        'http://localhost/api/v1/uploads/r1',
        'http://localhost/api/v1/installation/versions',
      ]) {
        expect(categoryOf(_groupFor(path)), HttpCategory.system, reason: path);
      }
    });
  });
}
