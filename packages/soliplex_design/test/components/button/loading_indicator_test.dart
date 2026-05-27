import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/src/components/button/loading_indicator.dart';

void main() {
  // Mirrors an input's suffix slot: loose width, tight (tall) height. An
  // ellipse would stretch the circle to the full height; an expanding wrapper
  // (e.g. Center) would push it to the full width.
  testWidgets('renders a square circle without expanding to fill the slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: DefaultTextStyle(
              style: const TextStyle(fontSize: 14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 200,
                  minHeight: 48,
                  maxHeight: 48,
                ),
                child: const ButtonLoadingIndicator(
                  foregroundColor: Colors.black,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(CircularProgressIndicator)),
      const Size(14, 14),
      reason: 'the spinner must stay a 14x14 circle, not stretch to an ellipse',
    );
    expect(
      tester.getSize(find.byType(ButtonLoadingIndicator)).width,
      14,
      reason: 'the indicator must not expand to fill the slot width',
    );
  });
}
