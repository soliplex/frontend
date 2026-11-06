import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds the preview title's paragraph showing [text].
///
/// The title adds invisible line breaks to what it shows, and announces
/// [text] in its place, so `find.text` with [text] matches neither.
Finder findPreviewTitle(String text) => find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().replaceAll('​', '') == text,
    );
