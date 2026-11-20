import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/svg_styles.dart';
import 'package:xml/xml.dart';

String _svg(String body) =>
    '<svg xmlns="http://www.w3.org/2000/svg" id="root" viewBox="0 0 10 10">'
    '$body</svg>';

/// The [name] attribute [inlineSvgStyles] leaves on the element with [id],
/// read as XML, the way flutter_svg reads it.
String? _attributeOf(String svg, String id, String name) =>
    XmlDocument.parse(svg)
        .descendantElements
        .where((e) => e.getAttribute('id') == id)
        .singleOrNull
        ?.getAttribute(name);

String? _styleOf(String svg, String id) => _attributeOf(svg, id, 'style');

/// The declarations in [style] as property: value.
Map<String, String> _declarations(String? style) => {
      for (final part in (style ?? '').split(';'))
        if (part.contains(':'))
          part.substring(0, part.indexOf(':')).trim():
              part.substring(part.indexOf(':') + 1).trim(),
    };

/// The colour flutter_svg paints at the centre of a 10x10 rendering.
///
/// flutter_svg prints a notice the first time in a process it meets an
/// element it does not draw; its notice for a `<style>` is allowed, and
/// anything else it prints fails the test.
Future<ui.Color> _centreColor(WidgetTester tester, String svg) async {
  final printed = <String>[];
  final pixel = await tester.runAsync(
    () => runZoned(
      () async {
        final info = await vg.loadPicture(SvgStringLoader(svg), null);
        final image = await info.picture.toImage(10, 10);
        final bytes = (await image.toByteData())!.buffer.asUint8List();
        const i = (5 * 10 + 5) * 4;
        return ui.Color.fromARGB(
          bytes[i + 3],
          bytes[i],
          bytes[i + 1],
          bytes[i + 2],
        );
      },
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) => printed.add(line),
      ),
    ),
  );
  expect(printed, everyElement(startsWith('unhandled element <style/>')));
  return pixel!;
}

void main() {
  group('inlineSvgStyles', () {
    test('returns an SVG without a style sheet unchanged', () {
      // Even a style flutter_svg cannot read: only an SVG with a sheet is
      // rewritten.
      final svg = _svg('<rect id="r" style="fill: red !important"/>');

      expect(inlineSvgStyles(svg), same(svg));
    });

    test('returns the SVG unchanged when no rule matches', () {
      final svg = _svg(
        '<style>.absent { fill: blue; }</style>'
        '<rect id="r" width="10" height="10"/>',
      );

      expect(inlineSvgStyles(svg), same(svg));
    });

    test('drops the style sheets once their rules are written out', () {
      final out = inlineSvgStyles(_svg(
        '<style>.x { fill: red; }</style><g><style>.y { fill: blue; }</style>'
        '</g><rect id="r" class="x"/>',
      ));

      expect(XmlDocument.parse(out).findAllElements('style'), isEmpty);
      expect(_declarations(_styleOf(out, 'r'))['fill'], 'red');
    });

    test('a more specific rule wins whatever its order', () {
      final out = inlineSvgStyles(_svg(
        '<style>#r { fill: blue; } .x { fill: green; } rect { fill: red; }'
        '</style><rect id="r" class="x"/><rect id="s" class="x"/>',
      ));

      expect(_declarations(_styleOf(out, 'r'))['fill'], 'blue');
      expect(_declarations(_styleOf(out, 's'))['fill'], 'green');
    });

    test('an attribute selector or pseudo-class weighs as a class', () {
      final out = inlineSvgStyles(_svg(
        '<style>[data-k] { fill: red; } rect:first-child { stroke: red; } '
        'g rect { fill: blue; stroke: blue; }</style>'
        '<g><rect id="r" data-k=""/></g>',
      ));

      expect(_declarations(_styleOf(out, 'r')), {
        'fill': 'red',
        'stroke': 'red',
      });
    });

    test(':not weighs as its argument', () {
      final out = inlineSvgStyles(_svg(
        '<style>rect:not(#x) { fill: red; } .a rect { fill: blue; }</style>'
        '<g class="a"><rect id="r"/></g>',
      ));

      expect(_declarations(_styleOf(out, 'r'))['fill'], 'red');
    });

    test('of equally specific rules, the later one wins', () {
      final out = inlineSvgStyles(_svg(
        '<style>.x { fill: red; } .y { fill: green; }</style>'
        '<rect id="r" class="y x"/>',
      ));

      expect(_declarations(_styleOf(out, 'r'))['fill'], 'green');
    });

    test("the element's own style attribute beats a rule", () {
      final out = inlineSvgStyles(_svg(
        '<style>#r { fill: red; stroke: red; }</style>'
        '<rect id="r" style="fill: green"/>',
      ));

      expect(_declarations(_styleOf(out, 'r')), {
        'fill': 'green',
        'stroke': 'red',
      });
    });

    test("rewrites an element's own style where no rule matches it", () {
      // flutter_svg reads neither a value carrying !important nor a CSS
      // transform, so every style is written as a rule's would be.
      final out = inlineSvgStyles(_svg(
        '<style>.absent { fill: blue; }</style>'
        '<rect id="r" style="fill: red !important"/>'
        '<rect id="t" style="transform: rotate(45deg)"/>',
      ));

      expect(_styleOf(out, 'r'), 'fill:red');
      expect(_styleOf(out, 't'), isNull);
      expect(_attributeOf(out, 't', 'transform'), 'rotate(45)');
    });

    test("keeps an element's own value when the rule beating it is dropped",
        () {
      // An !important rule beats the own fill in the cascade, but its value
      // cannot be resolved; the own fill, which the SVG as written draws,
      // stays.
      final out = inlineSvgStyles(_svg(
        '<style>.x { fill: var(--unset) !important; }</style>'
        '<rect id="r" class="x" style="fill: #ececff"/>',
      ));

      expect(_styleOf(out, 'r'), 'fill:#ececff');
    });

    test(
        'of two own declarations, the later one wins unless only the earlier '
        'is !important', () {
      final out = inlineSvgStyles(_svg(
        '<style>.x { stroke: red; }</style>'
        '<rect id="r" class="x" style="fill: red !important; fill: blue; '
        'opacity: 0.2; opacity: 0.5"/>',
      ));

      expect(_declarations(_styleOf(out, 'r'))['fill'], 'red');
      expect(_declarations(_styleOf(out, 'r'))['opacity'], '0.5');
    });

    test("keeps an element's own value the renderer cannot read", () {
      // A rule's would be dropped; the element's own is what it drew as
      // written.
      final out = inlineSvgStyles(_svg(
        '<style>.x { stroke: red; }</style>'
        '<rect id="r" class="x" style="fill: var(--unset)"/>',
      ));

      expect(_declarations(_styleOf(out, 'r')), {
        'fill': 'var(--unset)',
        'stroke': 'red',
      });
    });

    test('reads !important in any letter case', () {
      final out = inlineSvgStyles(_svg(
        '<style>.x { fill: red !IMPORTANT; } '
        '.y { fill: red !important; }</style>'
        '<rect id="r" class="x" style="fill: green"/>'
        '<rect id="s" class="y" style="fill: green !Important"/>',
      ));

      expect(_styleOf(out, 'r'), 'fill:red');
      expect(_styleOf(out, 's'), 'fill:green');
    });

    test('drops only the value the renderer would throw on', () {
      // flutter_svg throws on an hsl() colour with an angle unit, which
      // would fail the whole picture; the stroke is still drawn.
      final out = inlineSvgStyles(_svg(
        '<style>.x { fill: hsl(120deg 50% 50%); stroke: red; }</style>'
        '<rect id="r" class="x"/>'
        '<rect id="o" class="x" style="font-size: 120%; opacity: 0.5"/>',
      ));

      expect(_styleOf(out, 'r'), 'stroke:red');
      // The element's own, which as written would fail too.
      expect(_declarations(_styleOf(out, 'o')), {
        'opacity': '0.5',
        'stroke': 'red',
      });
    });

    test("drops a rule colour the renderer would silently ignore", () {
      // flutter_svg reads no oklch() colour and draws the parent's instead,
      // so the rule would hide the shape's fill="blue"; an own value it
      // ignores is kept as written, as the SVG as written draws it.
      final out = inlineSvgStyles(_svg(
        '<style>.x { fill: oklch(60% 0.2 250); stroke: red; }</style>'
        '<rect id="r" class="x" fill="blue"/>'
        '<rect id="o" style="fill: oklch(60% 0.2 250)"/>',
      ));

      expect(_styleOf(out, 'r'), 'stroke:red');
      expect(_styleOf(out, 'o'), 'fill:oklch(60% 0.2 250)');
    });

    test('keeps a rule colour that names no colour of its own', () {
      final out = inlineSvgStyles(_svg(
        '<style>.a { fill: none; stroke: currentColor; } '
        '.b { fill: url(#g); } .c { fill: inherit; }</style>'
        '<defs><linearGradient id="g"><stop offset="0" stop-color="red"/>'
        '</linearGradient></defs>'
        '<rect id="a" class="a"/><rect id="b" class="b"/>'
        '<rect id="c" class="c" fill="blue"/>',
      ));

      expect(_styleOf(out, 'a'), 'fill:none;stroke:currentColor');
      expect(_styleOf(out, 'b'), 'fill:url(#g)');
      // flutter_svg paints the parent's colour for inherit, as CSS does.
      expect(_styleOf(out, 'c'), 'fill:inherit');
    });

    test('keeps every own value of an SVG with more than it can check', () {
      // A scatter plot gives each point its own colour; past the check's
      // limit, a value goes unchecked rather than being dropped.
      final points = [
        for (var i = 0; i < 5000; i++)
          '<rect id="r$i" style="fill: #${i.toRadixString(16).padLeft(6, '0')}"/>',
      ].join();
      // Checked, this value would be dropped: flutter_svg throws on it.
      const unchecked = '<rect id="last" style="fill: hsl(120deg 50% 50%)"/>';
      final out = inlineSvgStyles(
        _svg('<style>* { stroke-linecap: butt; }</style>$points$unchecked'),
      );

      expect(_declarations(_styleOf(out, 'r4999'))['fill'], '#001387');
      expect(
        _declarations(_styleOf(out, 'last'))['fill'],
        'hsl(120deg 50% 50%)',
      );
    });

    test('takes a value flutter_svg rejects only in debug builds', () {
      // A transform with too many numbers fails one of flutter_svg's asserts,
      // which only debug builds run; the release answer is the one kept.
      final out = inlineSvgStyles(_svg(
        '<style>.x { stroke: red; }</style>'
        '<rect id="r" class="x" style="transform: translate(1 2 3)"/>',
      ));

      expect(_declarations(_styleOf(out, 'r')), {
        'transform': 'translate(1 2 3)',
        'stroke': 'red',
      });
    });

    test('checks a value the same way in debug and release builds', () {
      // flutter_svg reports an element it does not draw only from an assert,
      // so a value is tried on a <g> instead: this own width stays as
      // written.
      final out = inlineSvgStyles(_svg(
        '<style>.x { stroke: red; }</style>'
        '<other id="o" class="x" style="width: 5px"/>',
      ));

      expect(_declarations(_styleOf(out, 'o')), {
        'width': '5px',
        'stroke': 'red',
      });
    });

    test('skips a rule value the renderer cannot read', () {
      // flutter_svg reads neither an unset variable nor calc(), and a style
      // value it cannot read would still beat the element's attributes.
      final out = inlineSvgStyles(_svg(
        '<style>.x { fill: var(--c); stroke-width: CALC(1px + 2px); }</style>'
        '<rect id="r" class="x" fill="blue" stroke-width="3"/>',
      ));

      expect(_styleOf(out, 'r'), isNull);
      expect(_attributeOf(out, 'r', 'fill'), 'blue');
      expect(_attributeOf(out, 'r', 'stroke-width'), '3');
    });

    test(
        'of two declarations in one rule, the later one wins unless only '
        'the earlier is !important', () {
      final out = inlineSvgStyles(_svg(
        '<style>.x { fill: red !important; fill: green; '
        'stroke: red; stroke: blue; }</style>'
        '<rect id="r" class="x"/>',
      ));

      expect(_declarations(_styleOf(out, 'r')), {
        'fill': 'red',
        'stroke': 'blue',
      });
    });

    group('sets a shape attribute from a rule', () {
      test('on the elements it applies to', () {
        final out = inlineSvgStyles(_svg(
          '<style>circle { r: 4; cx: 5px; } rect { rx: 2px; width: 6; }'
          '</style><circle id="c"/><rect id="r"/>',
        ));

        expect(_styleOf(out, 'c'), 'r:4;cx:5px');
        expect(_styleOf(out, 'r'), 'rx:2px;width:6');
      });

      test('and not on others', () {
        // CSS x does nothing on a text, nor r on a rect; flutter_svg reads an
        // image's x with no unit, and throws on one.
        final out = inlineSvgStyles(_svg(
          '<style>.t { x: 10px; r: 3; }</style>'
          '<text id="t" class="t">a</text><rect id="r" class="t"/>'
          '<image id="i" class="t"/>',
        ));

        expect(_styleOf(out, 't'), isNull);
        expect(_styleOf(out, 'r'), 'x:10px');
        expect(_styleOf(out, 'i'), isNull);
      });

      test('only when it is a length the renderer reads', () {
        // Tried on the element's own kind, where flutter_svg throws on auto.
        final out = inlineSvgStyles(_svg(
          '<style>rect { rx: auto; height: 1em; }</style><rect id="r"/>',
        ));

        expect(_styleOf(out, 'r'), 'height:1em');
      });
    });

    group('converts a CSS transform', () {
      test('into the attribute syntax', () {
        final out = inlineSvgStyles(_svg(
          '<style>rect { transform: rotate(45deg) scale(0.8,0.8) '
          'translateX(2px) scaleY(3); }</style>'
          '<rect id="r"/>',
        ));

        // Written as the attribute: a browser reads a style value as CSS,
        // which this syntax is not.
        expect(_styleOf(out, 'r'), isNull);
        expect(
          _attributeOf(out, 'r', 'transform'),
          'rotate(45) scale(0.8 0.8) translate(2 0) scale(1 3)',
        );
      });

      test('about its origin', () {
        // mermaid's gantt milestone: a rotation from a rule about the
        // origin its attribute sets, which flutter_svg does not read.
        final out = inlineSvgStyles(_svg(
          '<style>.m { transform: rotate(45deg); } '
          '.n { transform: scale(2); transform-origin: 5px 5px; }</style>'
          '<rect id="m" class="m" transform-origin="709px 132px"/>'
          '<rect id="n" class="n"/>',
        ));

        expect(
          _attributeOf(out, 'm', 'transform'),
          'translate(709 132) rotate(45) translate(-709 -132)',
        );
        // Its origin is in the transform, and a browser would apply the
        // attribute a second time.
        expect(_attributeOf(out, 'm', 'transform-origin'), isNull);
        expect(
          _attributeOf(out, 'n', 'transform'),
          'translate(5 5) scale(2 2) translate(-5 -5)',
        );
      });

      test('in time linear in its length', () {
        // Retried from each letter, a long run of letters with no function
        // after it would take seconds.
        final stopwatch = Stopwatch()..start();
        final out = inlineSvgStyles(_svg(
          '<style>rect { transform: ${'a' * 30000}; fill: red; }</style>'
          '<rect id="r"/>',
        ));

        expect(_styleOf(out, 'r'), 'fill:red');
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      });

      test('none, which overrides the attribute', () {
        final out = inlineSvgStyles(_svg(
          '<style>rect { transform: none; }</style>'
          '<rect id="r" transform="translate(5)"/>',
        ));

        expect(_attributeOf(out, 'r', 'transform'), 'translate(0)');
      });

      test('and skips one without an equivalent', () {
        // A 3D function, a percentage, a unitless angle (invalid CSS), an
        // origin relative to a reference box, a non-default box, a
        // function generated SVGs do not use, and a number too large for a
        // double.
        final svg = _svg(
          '<style>#a { transform: translate3d(1px, 2px, 3px); } '
          '#b { transform: translate(50%); } #c { transform: rotate(45); } '
          '#d { transform: rotate(45deg); transform-origin: center; } '
          '#e { transform: rotate(45deg); transform-box: fill-box; } '
          '#f { transform: skewX(10deg); } '
          '#g { transform: translate(${'9' * 400}.5px); }</style>'
          '<rect id="a"/><rect id="b"/><rect id="c"/><rect id="d"/>'
          '<rect id="e"/><rect id="f"/><rect id="g"/>',
        );
        final out = inlineSvgStyles(svg);

        for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'g']) {
          expect(_styleOf(out, id), isNull, reason: id);
          expect(_attributeOf(out, id, 'transform'), isNull, reason: id);
        }
      });
    });

    group('expands the font shorthand', () {
      test('into the longhands the renderer reads', () {
        final out = inlineSvgStyles(_svg(
          '<style>.t { font: italic 600 14px/1.4 "Segoe UI", sans-serif; }'
          '</style><text id="t" class="t">a</text>',
        ));

        expect(_declarations(_styleOf(out, 't')), {
          'font-weight': '600',
          'font-size': '14px',
          'font-family': '"Segoe UI", sans-serif',
        });
      });

      test('resetting the weight it leaves out', () {
        final out = inlineSvgStyles(_svg(
          '<style>.t { font-weight: bold; } .t { font: 12px serif; }</style>'
          '<text id="t" class="t">a</text>',
        ));

        expect(
          _styleOf(out, 't'),
          'font-weight:normal;font-size:12px;font-family:serif',
        );
      });

      test('leaving out a weight the renderer cannot read', () {
        // flutter_svg reads normal, bold and 100 to 900, and warns on any
        // other weight; a value it warns about is dropped like one it throws
        // on.
        final out = inlineSvgStyles(_svg(
          '<style>.x { fill: red; }</style>'
          '<text id="t" style="font: bolder 12px serif">a</text>',
        ));

        expect(_styleOf(out, 't'), 'font-size:12px;font-family:serif');
      });

      test('in time linear in its length', () {
        // Read in quadratic time, a long run of spaces or of keywords would
        // take seconds.
        final stopwatch = Stopwatch()..start();
        final out = inlineSvgStyles(_svg(
          '<style>.x { fill: red; }</style>'
          '<text id="t" class="x" style="font: a${' ' * 30000}b">a</text>'
          '<text id="k" style="font: ${'normal ' * 40000}12px serif">a</text>',
        ));

        expect(_styleOf(out, 't'), 'fill:red');
        expect(_declarations(_styleOf(out, 'k'))['font-size'], '12px');
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      });

      test('with a line height, however it is spaced', () {
        final out = inlineSvgStyles(_svg(
          '<style>.t { font: 12px/ 1.4 serif; } .u { font: 12px / 1.4 serif; }'
          '</style><text id="t" class="t">a</text>'
          '<text id="u" class="u">a</text>',
        ));

        for (final id in ['t', 'u']) {
          expect(
            _styleOf(out, id),
            'font-weight:normal;font-size:12px;font-family:serif',
            reason: id,
          );
        }
      });

      test('and skips one it cannot read', () {
        // A system font, and a stretch, which generated SVGs do not write.
        final out = inlineSvgStyles(_svg(
          '<style>.t { font: caption; fill: red; } '
          '.u { font: condensed 12px serif; fill: red; }</style>'
          '<text id="t" class="t">a</text><text id="u" class="u">a</text>',
        ));

        expect(_styleOf(out, 't'), 'fill:red');
        expect(_styleOf(out, 'u'), 'fill:red');
      });
    });

    group('resolves a variable', () {
      test('set on :root', () {
        final out = inlineSvgStyles(_svg(
          '<style>:root { --accent: #00ff00; } '
          '.box { fill: var(--accent); }</style>'
          '<rect id="r" class="box"/>',
        ));

        expect(_styleOf(out, 'root'), isNull);
        expect(_styleOf(out, 'r'), 'fill:#00ff00');
      });

      test('set on an ancestor, and only beneath it', () {
        final out = inlineSvgStyles(_svg(
          '<style>.theme { --c: red; } .box { fill: var(--c); }</style>'
          '<g class="theme"><rect id="in" class="box"/></g>'
          '<rect id="out" class="box" fill="blue"/>',
        ));

        expect(_styleOf(out, 'in'), 'fill:red');
        expect(_styleOf(out, 'out'), isNull);
      });

      test('to its fallback when it is not set', () {
        final out = inlineSvgStyles(_svg(
          '<style>.box { fill: var(--missing, var(--also-missing, red)); }'
          '</style><rect id="r" class="box"/>',
        ));

        expect(_styleOf(out, 'r'), 'fill:red');
      });

      test('that refers to another, where the other is set', () {
        // --b is read where --a is set, on the root, not on the rect.
        final out = inlineSvgStyles(_svg(
          '<style>:root { --a: var(--b); --b: red; } '
          '.box { --b: blue; fill: var(--a); }</style>'
          '<rect id="r" class="box"/>',
        ));

        expect(_styleOf(out, 'r'), 'fill:red');
      });

      test("in an element's own style", () {
        final out = inlineSvgStyles(_svg(
          '<style>:root { --c: red; }</style>'
          '<rect id="r" style="fill: var(--c)"/>',
        ));

        expect(_styleOf(out, 'r'), 'fill:red');
      });

      test(
          'that uses another many times over, by dropping it, '
          'without stalling', () {
        // Each variable uses the one before it six times, and the first is
        // empty, so the value stays short while the uses multiply: 7776 at
        // the last.
        final chain = [
          '--v0: var(--unset,);',
          for (var i = 1; i <= 5; i++)
            '--v$i: ${List.filled(6, 'var(--v${i - 1})').join()};',
        ].join(' ');
        final out = inlineSvgStyles(_svg(
          '<style>:root { $chain } .box { stroke: var(--v5) red; '
          'fill: red; }</style><rect id="r" class="box"/>',
        ));

        expect(_styleOf(out, 'r'), 'fill:red');
      });

      test('that refers to itself, by its fallback, as CSS does', () {
        final out = inlineSvgStyles(_svg(
          '<style>:root { --a: var(--a); } .x { fill: var(--a, red); }'
          '</style><rect id="r" class="x"/>',
        ));

        expect(_styleOf(out, 'r'), 'fill:red');
      });

      test('in time linear in how deep its element is', () {
        // Walking up from each of 200 uses on each of 1000 nested groups
        // would visit every group above it each time.
        final stopwatch = Stopwatch()..start();
        final out = inlineSvgStyles(_svg(
          '<style>g { stroke: ${List.filled(200, 'var(--m,)').join()}red; }'
          '</style>${'<g>' * 999}<g id="g"/>${'</g>' * 999}',
        ));

        expect(_styleOf(out, 'g'), 'stroke:red');
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      });

      test('that grows longer than the SVG, by dropping it', () {
        // Each use copies a long value, so 200 of them would make the SVG
        // hundreds of times larger.
        final out = inlineSvgStyles(_svg(
          '<style>svg { --long: "${'a' * 1000}"; } '
          '.box { font-family: ${List.filled(200, 'var(--long)').join(',')}; '
          'fill: red; }</style><text id="t" class="box">a</text>',
        ));

        expect(_styleOf(out, 't'), 'fill:red');
      });
    });

    test('reads a rule with many selectors in time linear in its size', () {
      // Read per selector, the 2000 declarations would be read 2000 times.
      final selectors = [for (var i = 0; i < 2000; i++) '.c$i'].join(',');
      final declarations = [for (var i = 0; i < 2000; i++) '--v$i: 1;'].join();
      final stopwatch = Stopwatch()..start();
      final out = inlineSvgStyles(_svg(
        '<style>$selectors { $declarations fill: red; }</style>'
        '<rect id="r" class="c1999"/>',
      ));

      expect(_styleOf(out, 'r'), 'fill:red');
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('skips one selector of a group and keeps the others', () {
      // package:html would match rect:nth-child(1) to the rect, which is the
      // second child.
      final out = inlineSvgStyles(_svg(
        '<style>rect:nth-child(1), .x { fill: red; } '
        'rect:nth-child(1) { fill: blue; }</style>'
        '<rect id="r" class="x"/>',
      ));

      expect(_declarations(_styleOf(out, 'r'))['fill'], 'red');
    });

    test('skips a selector with the ~ combinator', () {
      // package:html's ~ costs the cube of the number of siblings: seconds
      // for a few thousand shapes.
      final out = inlineSvgStyles(_svg(
        '<style>.x ~ rect { fill: red; } rect { stroke: red; }</style>'
        '<rect class="x"/><rect id="r"/>',
      ));

      expect(_declarations(_styleOf(out, 'r')), {'stroke': 'red'});
    });

    test('skips a selector with a namespace and keeps the others', () {
      final out = inlineSvgStyles(_svg(
        '<style>svg|rect { fill: red; } rect { stroke: red; }</style>'
        '<rect id="r"/>',
      ));

      expect(_declarations(_styleOf(out, 'r')), {'stroke': 'red'});
    });

    test('skips a selector package:html rejects and keeps the others', () {
      // csslib reads `g >. rect` from the sheet; package:html, given the
      // selector alone, rejects it.
      final out = inlineSvgStyles(_svg(
        '<style>g >. rect { fill: red; } rect { stroke: red; }</style>'
        '<g><rect id="r"/></g>',
      ));

      expect(_declarations(_styleOf(out, 'r')), {'stroke': 'red'});
    });

    test('applies the child-position pseudo-classes', () {
      final out = inlineSvgStyles(_svg(
        '<style>g > rect:first-child { fill: red; } '
        'g > rect:last-child { stroke: red; } '
        'rect:only-child { opacity: 0.5; }</style>'
        '<g><rect id="a"/><rect id="b"/></g><g><rect id="c"/></g>',
      ));

      expect(_declarations(_styleOf(out, 'a')), {'fill': 'red'});
      expect(_declarations(_styleOf(out, 'b')), {'stroke': 'red'});
      expect(_declarations(_styleOf(out, 'c')), {
        'fill': 'red',
        'stroke': 'red',
        'opacity': '0.5',
      });
    });

    test('skips a pseudo-class the selector engine would match wrongly', () {
      // package:html counts :nth-child from 0, and takes :link to be any
      // element with an href.
      final out = inlineSvgStyles(_svg(
        '<style>:link { stroke: red; } '
        'rect:not(:nth-child(1)) { opacity: 0.5; }</style>'
        '<rect id="a"/><use id="u" href="#a"/><rect id="b"/>',
      ));

      expect(_styleOf(out, 'u'), isNull);
      expect(_styleOf(out, 'b'), isNull);
    });

    test('ignores a sheet that applies only under a media query', () {
      // As a rule inside @media is ignored; a sheet for all or for screens
      // applies.
      final out = inlineSvgStyles(_svg(
        '<style media="(prefers-color-scheme: dark)">.x { fill: black; }'
        '</style><style media="print">.x { stroke: black; }</style>'
        '<style media="screen">.x { opacity: 0.5; }</style>'
        '<rect id="r" class="x"/>',
      ));

      expect(_styleOf(out, 'r'), 'opacity:0.5');
    });

    test('ignores rules inside at-rules', () {
      final out = inlineSvgStyles(_svg(
        '<style>.x { fill: red; } '
        '@media (prefers-color-scheme: dark) { .x { fill: black; } }</style>'
        '<rect id="r" class="x"/>',
      ));

      expect(_declarations(_styleOf(out, 'r'))['fill'], 'red');
    });

    test('keeps the elements after an element HTML would close the SVG on', () {
      final out = inlineSvgStyles(_svg(
        '<style>.x { fill: red; }</style>'
        '<rect id="a" class="x"/><span>t</span><circle id="b" class="x"/>',
      ));

      expect(_declarations(_styleOf(out, 'a'))['fill'], 'red');
      expect(_declarations(_styleOf(out, 'b'))['fill'], 'red');
    });

    test('returns an SVG too large to inline quickly unchanged', () {
      // Over a megabyte, more rules times elements than it can match in a
      // fraction of a second on the UI thread, or styles that would write out
      // more than a megabyte; drawn unstyled, as written.
      final long = _svg(
        '<style>.x { fill: red; }</style><rect class="x"/>'
        '<desc>${'a' * (1 << 20)}</desc>',
      );
      final crowded = _svg(
        '<style>${[
          for (var i = 0; i < 2000; i++) '.c$i { fill: red; }'
        ].join()}'
        '</style>${'<rect class="c0"/>' * 1000}',
      );
      // One rule's long value copied onto each of many elements.
      final copious = _svg(
        '<style>g { font-family: ${'a' * 50000}; }</style>${'<g/>' * 2000}',
      );

      // Compared by identity, so a failure does not print a megabyte.
      expect(identical(inlineSvgStyles(long), long), isTrue);
      expect(identical(inlineSvgStyles(crowded), crowded), isTrue);
      expect(identical(inlineSvgStyles(copious), copious), isTrue);
    });

    test('returns an SVG that is not well-formed XML unchanged', () {
      final svg = _svg(
        '<style>.x { fill: red; }</style><rect id="r" class="x"><g>',
      );

      expect(inlineSvgStyles(svg), same(svg));
    });

    test('matches a type selector written in camelCase', () {
      final out = inlineSvgStyles(_svg(
        '<style>linearGradient stop { stop-color: red; }</style>'
        '<defs><linearGradient><stop id="s" offset="0"/></linearGradient>'
        '</defs>',
      ));

      expect(_declarations(_styleOf(out, 's'))['stop-color'], 'red');
    });

    test('inlines only properties the renderer reads', () {
      // flutter_svg reads no font-style, user-select or filter.
      final out = inlineSvgStyles(_svg(
        '<style>.x { fill: red; font-style: italic; '
        '-webkit-user-select: none; filter: drop-shadow(1px 1px 1px); }'
        '</style>'
        '<rect id="r" class="x"/>',
      ));

      expect(_declarations(_styleOf(out, 'r')), {'fill': 'red'});
    });

    test('keeps a value with commas and quotes whole', () {
      final out = inlineSvgStyles(_svg(
        '<style>.x { font-family: "trebuchet ms", verdana, sans-serif; '
        'fill: hsl(240, 100%, 46%); }</style>'
        '<text id="t" class="x">a</text>',
      ));

      expect(_declarations(_styleOf(out, 't')), {
        'font-family': '"trebuchet ms", verdana, sans-serif',
        'fill': 'hsl(240, 100%, 46%)',
      });
    });
  });

  group('inlineSvgStyles rendered by flutter_svg', () {
    testWidgets('a rule beats a presentation attribute written after style',
        (tester) async {
      final svg = _svg(
        '<style>.box { fill: #00ff00; }</style>'
        '<rect style="stroke:none" class="box" fill="#ff0000" '
        'width="10" height="10"/>',
      );

      expect(
        await _centreColor(tester, inlineSvgStyles(svg)),
        const ui.Color(0xFF00FF00),
      );
    });
  });
}
