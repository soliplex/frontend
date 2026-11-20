@TestOn('browser')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/content_viewer/browser_svg_picture.dart';
import 'package:soliplex_frontend/src/modules/room/ui/content_viewer/svg_image_element_web.dart';

void main() {
  testWidgets('browser rejection is reported at zero area', (tester) async {
    Object? rejection;
    await tester.pumpWidget(
      Align(
        child: BrowserSvgPicture(
          '<svg xmlns="http://www.w3.org/2000/svg" width="0" '
          'viewBox="0 0 20 10"><rect></svg>',
          onFailed: (error, _) => rejection = error,
        ),
      ),
    );
    expect(tester.getSize(find.byType(HtmlElementView)), Size.zero);
    for (var frame = 0; frame < 100 && rejection == null; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(rejection, isA<SvgImageRejected>());
  });
}
