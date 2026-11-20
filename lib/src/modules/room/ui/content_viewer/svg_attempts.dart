/// What draws an SVG: the browser, as an image, or flutter_svg.
enum SvgRenderer { browser, flutterSvg }

/// One way of drawing an SVG: a [renderer] and the [svg] text it is given.
typedef SvgAttempt = ({SvgRenderer renderer, String svg});

/// Why an attempt failed to draw.
typedef SvgFailure = ({Object error, StackTrace? stackTrace});

/// What a failure reported to [SvgAttempts.fail] leads to.
enum SvgFailureOutcome {
  /// The attempt is no longer current, or its failure was already reported:
  /// nothing changes.
  alreadyHandled,

  /// The next attempt is current.
  nextAttempt,

  /// The last attempt failed: none is left.
  allFailed,
}

/// The ways to draw one SVG, tried in order until one draws.
///
/// In a browser: the browser with the content as written, then flutter_svg
/// with its `<style>` rules inlined, then flutter_svg with the content as
/// written. Elsewhere the browser is left out. A [partial] SVG, one still
/// streaming that may not be whole, is drawn by flutter_svg as written only:
/// it can change on every chunk, and both the browser's image and inlining
/// take the whole document each time.
///
/// An attempt is skipped when one before it gave the same renderer the same
/// text, as when inlining leaves the SVG unchanged; the browser's failure
/// still leaves flutter_svg its turn with that text. [inlineStyles] runs only
/// when its attempt is reached, so an SVG the browser draws is never inlined.
class SvgAttempts {
  SvgAttempts(
    String content, {
    required bool inBrowser,
    required bool partial,
    required String Function(String svg) inlineStyles,
  }) : _pending = [
          if (inBrowser && !partial)
            () => (renderer: SvgRenderer.browser, svg: content),
          if (!partial)
            () =>
                (renderer: SvgRenderer.flutterSvg, svg: inlineStyles(content)),
          () => (renderer: SvgRenderer.flutterSvg, svg: content),
        ] {
    _advance();
  }

  final List<SvgAttempt Function()> _pending;
  final List<SvgAttempt> _tried = [];
  SvgFailure? _failure;

  /// The attempt to draw: the first, or the one the last failure moved to.
  /// Once [failure] is set, the attempt that failed last.
  SvgAttempt get current => _tried.last;

  /// The last attempt's failure, once every attempt has failed; null until
  /// then.
  SvgFailure? get failure => _failure;

  /// Reports that [attempt] failed to draw, with [error] and [stackTrace].
  /// Only the current attempt's first failure advances the sequence.
  SvgFailureOutcome fail(
    SvgAttempt attempt,
    Object error,
    StackTrace? stackTrace,
  ) {
    if (_failure != null || attempt != current) {
      return SvgFailureOutcome.alreadyHandled;
    }
    if (_advance()) return SvgFailureOutcome.nextAttempt;
    _failure = (error: error, stackTrace: stackTrace);
    return SvgFailureOutcome.allFailed;
  }

  /// Moves to the next attempt, returning false, and staying on the last
  /// one, when there is none left.
  bool _advance() {
    while (_pending.isNotEmpty) {
      final next = _pending.removeAt(0)();
      if (_tried.contains(next)) continue;
      _tried.add(next);
      return true;
    }
    return false;
  }
}
