@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/host_resolution.dart';

void main() {
  test('a name that does not resolve is reported as a lookup failure',
      () async {
    // .invalid is reserved by RFC 2606 precisely so it can never resolve.
    final description =
        await describeHostResolution('nonexistent.example.invalid');

    expect(description, startsWith('lookup failed:'));
  });

  test('a name that resolves reports a count and family, not addresses',
      () async {
    // Loopback resolves without leaving the machine, so this does not depend
    // on the network the suite runs on.
    final description = await describeHostResolution('localhost');

    expect(description, startsWith('resolved to'));
    expect(description, contains('address(es)'));
    // The addresses themselves stay out of the report.
    expect(description, isNot(contains('127.0.0.1')));
  });
}
