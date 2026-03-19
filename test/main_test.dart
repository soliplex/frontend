import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/flavors.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';

import 'helpers/fakes.dart';

void main() {
  testWidgets('app boots and renders home screen', (tester) async {
    final config = await standard(storage: InMemoryTokenStorage());
    runSoliplexShell(config);
    await tester.pumpAndSettle();

    expect(find.text('Soliplex'), findsOneWidget);
  });
}
