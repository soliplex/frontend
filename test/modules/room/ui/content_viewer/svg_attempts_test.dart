import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/content_viewer/svg_attempts.dart';

const _content = '<svg>written</svg>';
const _inlined = '<svg>inlined</svg>';
final _error = StateError('failed');

String _changes(String svg) => _inlined;
String _leavesUnchanged(String svg) => svg;

/// Every attempt [attempts] makes, the current one first, failing each in
/// turn.
List<SvgAttempt> _all(SvgAttempts attempts) => [
      attempts.current,
      for (;
          attempts.fail(attempts.current, _error, null) ==
              SvgFailureOutcome.nextAttempt;)
        attempts.current,
    ];

void main() {
  group('SvgAttempts', () {
    test('natively draws the inlined SVG, then the SVG as written', () {
      expect(
        _all(
          SvgAttempts(
            _content,
            inBrowser: false,
            partial: false,
            inlineStyles: _changes,
          ),
        ),
        [
          (renderer: SvgRenderer.flutterSvg, svg: _inlined),
          (renderer: SvgRenderer.flutterSvg, svg: _content),
        ],
      );
    });

    test('natively draws once when inlining leaves the SVG unchanged', () {
      expect(
        _all(
          SvgAttempts(
            _content,
            inBrowser: false,
            partial: false,
            inlineStyles: _leavesUnchanged,
          ),
        ),
        [(renderer: SvgRenderer.flutterSvg, svg: _content)],
      );
    });

    test('in a browser, tries the browser, then the inlined and written SVG',
        () {
      expect(
        _all(
          SvgAttempts(
            _content,
            inBrowser: true,
            partial: false,
            inlineStyles: _changes,
          ),
        ),
        [
          (renderer: SvgRenderer.browser, svg: _content),
          (renderer: SvgRenderer.flutterSvg, svg: _inlined),
          (renderer: SvgRenderer.flutterSvg, svg: _content),
        ],
      );
    });

    test(
        'in a browser, falls back to flutter_svg with the same text when '
        'inlining leaves it unchanged', () {
      // A CSP that blocks data: images fails the browser on a plain SVG;
      // flutter_svg must still draw it.
      expect(
        _all(
          SvgAttempts(
            _content,
            inBrowser: true,
            partial: false,
            inlineStyles: _leavesUnchanged,
          ),
        ),
        [
          (renderer: SvgRenderer.browser, svg: _content),
          (renderer: SvgRenderer.flutterSvg, svg: _content),
        ],
      );
    });

    test('inlines only once the browser has failed', () {
      var inlined = 0;
      final attempts = SvgAttempts(
        _content,
        inBrowser: true,
        partial: false,
        inlineStyles: (svg) {
          inlined++;
          return _inlined;
        },
      );
      expect(inlined, 0);

      attempts.fail(attempts.current, _error, null);
      expect(
          attempts.current, (renderer: SvgRenderer.flutterSvg, svg: _inlined));
      expect(inlined, 1);

      attempts.fail(attempts.current, _error, null);
      expect(inlined, 1);
    });

    test('draws a partial SVG as written with flutter_svg, without inlining',
        () {
      for (final inBrowser in [true, false]) {
        var inlined = 0;
        final attempts = SvgAttempts(
          _content,
          inBrowser: inBrowser,
          partial: true,
          inlineStyles: (svg) {
            inlined++;
            return _inlined;
          },
        );
        expect(
          _all(attempts),
          [(renderer: SvgRenderer.flutterSvg, svg: _content)],
          reason: 'inBrowser: $inBrowser',
        );
        expect(inlined, 0, reason: 'inBrowser: $inBrowser');
      }
    });

    test('moves on once when the same attempt fails twice', () {
      // flutter_svg's error builder runs on every rebuild while its picture
      // is mounted, so an attempt's failure can be reported more than once.
      final attempts = SvgAttempts(
        _content,
        inBrowser: true,
        partial: false,
        inlineStyles: _changes,
      );
      const browser = (renderer: SvgRenderer.browser, svg: _content);
      const inlined = (renderer: SvgRenderer.flutterSvg, svg: _inlined);

      expect(
          attempts.fail(browser, _error, null), SvgFailureOutcome.nextAttempt);
      expect(attempts.fail(browser, _error, null),
          SvgFailureOutcome.alreadyHandled);
      expect(attempts.current, inlined);
    });

    test('reports every attempt failed once, keeping the last', () {
      final attempts = SvgAttempts(
        _content,
        inBrowser: false,
        partial: false,
        inlineStyles: _changes,
      );
      const written = (renderer: SvgRenderer.flutterSvg, svg: _content);

      expect(attempts.fail(attempts.current, _error, null),
          SvgFailureOutcome.nextAttempt);
      expect(attempts.fail(written, _error, null), SvgFailureOutcome.allFailed);
      expect(attempts.fail(written, _error, null),
          SvgFailureOutcome.alreadyHandled);
      expect(attempts.current, written);
    });

    test('keeps the last failure once every attempt failed, and only it', () {
      final attempts = SvgAttempts(
        _content,
        inBrowser: false,
        partial: false,
        inlineStyles: _changes,
      );
      final first = StateError('inlined failed');
      final last = StateError('written failed');
      final trace = StackTrace.current;

      attempts.fail(attempts.current, first, null);
      expect(attempts.failure, isNull);

      final written = attempts.current;
      attempts.fail(written, last, trace);
      expect(attempts.failure, (error: last, stackTrace: trace));

      attempts.fail(written, StateError('reported again'), null);
      expect(attempts.failure, (error: last, stackTrace: trace));
    });
  });
}
