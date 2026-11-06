import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds a paragraph showing [text] once its zero-width spaces are removed;
/// scope it to the preview, where a list row may show the same text.
///
/// The preview title adds zero-width spaces, places a line may break, to the
/// text it shows, which `find.text` with [text] so does not match; [text] is
/// what it announces instead, which `find.text` does not read.
Finder findPreviewTitle(String text) => find.byWidgetPredicate(
      (w) =>
          w is RichText &&
          w.text.toPlainText().replaceAll('\u200B', '') == text,
    );
