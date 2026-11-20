import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' as css;
import 'package:html/dom.dart' as html;
import 'package:xml/xml.dart';

import 'svg_styles/css_transform.dart';
import 'svg_styles/font_shorthand.dart';
import 'svg_styles/value_check.dart';

/// Returns [svg] with the rules of its `<style>` sheets written into each
/// matching element's `style` attribute, because flutter_svg reads `style`
/// attributes but ignores `<style>` elements.
///
/// Selectors are matched by package:html: type, class, id, attribute, `*`,
/// the descendant, child (`>`) and next-sibling (`+`) combinators, `:root`,
/// `:first-child`, `:last-child`, `:only-child`, and `:not` over any of
/// those. A selector with the `~` combinator, any other pseudo-class (such
/// as `:hover` or `:nth-child`), a pseudo-element, a named namespace, or one
/// package:html rejects is skipped, as are rules inside at-rules (`@media`,
/// `@keyframes`) and sheets for other media (`<style media="print">`).
/// package:html does not backtrack, so a descendant combinator after a `>` or
/// `+` (`.a > .b .c`) can miss an element a browser would match. The sheet is
/// parsed by csslib, which recovers from a selector it cannot parse
/// (`:where()`, `:not(.a, .b)`) by skipping ahead, and can lose the rules
/// after it.
///
/// The cascade follows CSS: an `!important` declaration beats one without;
/// of equal importance, the element's own `style` beats a rule; among rules,
/// higher specificity wins, then later position. Only the properties
/// [_taken] names are taken from rules, a `font` shorthand's longhands among
/// them. A `var()` is resolved where its custom property is set (see
/// [_Variables]). A value flutter_svg would throw on or warn about is dropped
/// on its own, asked of flutter_svg's parser (see [ValueCheck]), and the rest
/// of the element's styles are kept; one that fails only in the whole SVG
/// reaches flutter_svg, and `SvgBody` then draws the SVG as written. Once
/// rules are written out, the `<style>` elements are dropped.
///
/// Every element's own `style` is rewritten the same way, whether or not a
/// rule matched it. An SVG with no `<style>` element, one with no rule that
/// applies and no element with a `style`, or one that is not well-formed XML
/// is returned unchanged, as is one too large to inline quickly on the UI
/// thread (see [_maxSvgLength] and [_maxMatches]).
String inlineSvgStyles(String svg) {
  if (!svg.contains('<style') || svg.length > _maxSvgLength) return svg;
  final XmlDocument document;
  try {
    document = XmlDocument.parse(svg);
  } on XmlException {
    // Returned as written, unstyled: flutter_svg reads it with xml's event
    // parser, which does not check nesting, so it may still draw it (an
    // SVG cut off before its `</svg>`) or fail and report it.
    return svg;
  }
  final root = document.rootElement;
  final elements = [root, ...root.descendantElements];
  final sheets = [
    for (final element in elements)
      if (element.localName == 'style') element,
  ];
  final rules = _rules([
    for (final sheet in sheets)
      if (_unconditional(sheet)) sheet,
  ]);
  if (rules.length * elements.length > _maxMatches) return svg;
  final mirror = _Mirror(root);

  final styled = <XmlElement, Map<String, _Declaration>>{};
  for (final rule in rules) {
    final List<XmlElement> matched;
    try {
      matched = mirror.select(rule.selector);
    } on UnimplementedError {
      // package:html throws for a selector it does not evaluate, such as
      // one with a namespace.
      continue;
    } on FormatException {
      // package:html re-reads each selector alone, and can reject one
      // csslib read from the sheet (`g >. rect`).
      continue;
    }
    for (final element in matched) {
      final declarations = styled.putIfAbsent(
        element,
        () => _ownDeclarations(element),
      );
      for (final declaration in rule.declarations) {
        final candidate = declaration.inRule(rule);
        final current = declarations[candidate.property];
        if (current == null || candidate.beats(current)) {
          declarations[candidate.property] = candidate;
        }
      }
    }
  }
  for (final element in elements) {
    if (element.getAttribute('style') != null) {
      styled.putIfAbsent(element, () => _ownDeclarations(element));
    }
  }

  if (styled.isEmpty) return svg;
  final variables = _Variables(styled, svg.length);
  final check = ValueCheck();
  var writtenLength = 0;
  for (final MapEntry(key: element, value: declarations) in styled.entries) {
    final style = <String>[];
    final own = _ownDeclarations(element);
    for (final d in declarations.values) {
      // A rule that beat the element's own value but is dropped leaves the
      // own value, which the SVG as written draws.
      final written = _write(d, element, declarations, variables, check) ??
          switch (d.own ? null : own[d.property]) {
            final ownValue? =>
              _write(ownValue, element, declarations, variables, check),
            null => null,
          };
      switch (written) {
        case (_Target.style, final value):
          style.add('${d.property}:$value');
        case (_Target.transform, final value):
          // A browser reads a style value as CSS, which the attribute's
          // syntax is not. The transform turns about the origin it was given,
          // which a browser would otherwise apply a second time.
          element.setAttribute('transform', value);
          element.removeAttribute('transform-origin');
        case null:
          break;
      }
      // A rule's value is copied onto every element it matches, so a long one
      // matching many elements could write out far more than the SVG holds.
      writtenLength += written?.$2.length ?? 0;
      if (writtenLength > _maxSvgLength) return svg;
    }
    // Rewritten even where only the element's own declarations won, because
    // flutter_svg cannot read a value that still carries `!important`.
    // Written last, because flutter_svg lets a later attribute win and a
    // rule must beat a presentation attribute such as fill="...".
    element.removeAttribute('style');
    if (style.isNotEmpty) element.setAttribute('style', style.join(';'));
  }
  // Their rules now live on the elements, and in debug builds flutter_svg
  // prints a notice for a <style> element it skips.
  for (final style in sheets) {
    style.remove();
  }
  return document.toXmlString();
}

/// Whether [sheet] applies whatever the display: it has no `media`
/// attribute, or one for all media or for screens. A sheet for print or for
/// a media query (`prefers-color-scheme: dark`) is skipped, as a rule inside
/// `@media` is.
bool _unconditional(XmlElement sheet) => const {null, '', 'all', 'screen'}
    .contains(sheet.getAttribute('media')?.trim().toLowerCase());

/// Longer than this, an SVG, or the styles it would have written out, is
/// returned unchanged: reading, copying and writing it out alone would hold
/// the UI thread for a visible time.
const _maxSvgLength = 1 << 20;

/// Past this many rules times elements, an SVG is returned unchanged: each
/// rule is matched against every element, about a tenth of a second per
/// million pairs.
const _maxMatches = 2000000;

/// The elements of an XML tree as a package:html tree, so package:html's
/// selector engine can match against them.
///
/// The mirror holds elements and attributes only: text and comments take no
/// part in matching. Names are lowercased, because package:html lowercases a
/// selector's type and attribute names before it compares them. package:html
/// matches `:root` only on an `<html>` element, so the mirror marks its root
/// and selects the mark in its place.
class _Mirror {
  _Mirror(XmlElement root) {
    _top.append(_copy(root)..attributes[_rootMark] = '');
  }

  static const _rootMark = 'data-inline-svg-styles-root';
  static final _root = RegExp(r':root(?![\w-])');

  final _top = html.DocumentFragment();
  final _elements = <html.Element, XmlElement>{};

  List<XmlElement> select(String selector) => [
        for (final match in _top.querySelectorAll(
          selector.replaceAll(_root, '[$_rootMark]'),
        ))
          _elements[match]!,
      ];

  html.Element _copy(XmlElement element) {
    final copy = html.Element.tag(element.localName.toLowerCase());
    for (final attribute in element.attributes) {
      copy.attributes[attribute.qualifiedName.toLowerCase()] = attribute.value;
    }
    for (final child in element.childElements) {
      copy.append(_copy(child));
    }
    _elements[copy] = element;
    return copy;
  }
}

/// SVG presentation properties whose CSS value flutter_svg parses the same
/// way as the attribute, though it throws on some valid CSS values (such as
/// `text-decoration: underline dotted`), which [ValueCheck] leaves out. The
/// shape attributes ([_shapeAttributes]) are taken too, where they apply.
/// `transform` is converted to the attribute's syntax (see [svgTransform]).
/// `filter` is left
/// out: flutter_svg draws no filter.
const _inlinedProperties = {
  'clip-path',
  'clip-rule',
  'color',
  'display',
  'fill',
  'fill-opacity',
  'fill-rule',
  'font-family',
  'font-size',
  'font-weight',
  'mask',
  'opacity',
  'stop-color',
  'stop-opacity',
  'stroke',
  'stroke-dasharray',
  'stroke-dashoffset',
  'stroke-linecap',
  'stroke-linejoin',
  'stroke-miterlimit',
  'stroke-opacity',
  'stroke-width',
  'text-anchor',
  'text-decoration',
  'transform',
  'visibility',
};

/// Properties taken from rules only to place a `transform`, and not written:
/// flutter_svg reads neither.
const _transformLayout = {'transform-origin', 'transform-box'};

// Matched here rather than taken from csslib, whose tokenizer recognises only
// a lowercase `!important` with no space after the `!`.
final _important = RegExp(r'!\s*important\s*$', caseSensitive: false);

/// The CSS function generated SVGs use that flutter_svg cannot read, and
/// that is left once variables are resolved. A rule value using it would
/// beat a presentation attribute it can read.
final _unreadable = RegExp(r'\bcalc\(', caseSensitive: false);

final _variable = RegExp(r'\bvar\(', caseSensitive: false);

/// Whether a rule's [property] is taken: one flutter_svg reads, a custom
/// property a `var()` may read, or one that places a `transform`.
bool _taken(String property) =>
    _inlinedProperties.contains(property) ||
    _shapeAttributes.containsKey(property) ||
    _transformLayout.contains(property) ||
    property.startsWith('--');

/// Where a declaration is written on its element.
enum _Target { style, transform }

/// [declaration] as written on [element]: where it goes and its value, with
/// variables resolved; null when it is not written. A custom property, or
/// one that only places a `transform`, is read by others and not written. A
/// rule value flutter_svg cannot read, or a shape attribute on an element it
/// does not apply to, is dropped, so a presentation attribute applies where
/// the element has one (the cascade has already discarded any lower rule; a
/// browser would use the inherited or initial value for an unresolved
/// `var()`); the element's own is then written as it is, without its
/// `!important`. Either is dropped where flutter_svg would throw on or warn
/// about it (see [ValueCheck]); one it throws on would otherwise fail the
/// whole SVG. A rule's colour flutter_svg would silently ignore is dropped
/// too (see [ValueCheck.colours]): written, it would hide the element's
/// `fill` or `stroke` attribute behind the parent's colour.
(_Target, String)? _write(
  _Declaration declaration,
  XmlElement element,
  Map<String, _Declaration> declarations,
  _Variables variables,
  ValueCheck check,
) {
  final property = declaration.property;
  if (property.startsWith('--') || _transformLayout.contains(property)) {
    return null;
  }
  final value = variables.resolve(declaration.value, element);
  if (value != null &&
      !_unreadable.hasMatch(value) &&
      _appliesTo(property, element)) {
    if (property == 'transform') {
      final origin = _transformOrigin(element, declarations, variables);
      final transform = origin == null ? null : svgTransform(value, origin);
      if (transform != null) return (_Target.transform, transform);
    } else if (_passes(check, property, value, element) &&
        (declaration.own || check.colours(property, value))) {
      return (_Target.style, value);
    }
  }
  if (declaration.own && _passes(check, property, declaration.value, element)) {
    return (_Target.style, declaration.value);
  }
  return null;
}

/// Whether [property] applies to [element]: a shape attribute only to the
/// elements [_shapeAttributes] names, any other to all.
bool _appliesTo(String property, XmlElement element) =>
    _shapeAttributes[property]?.contains(element.localName) ?? true;

/// Whether flutter_svg takes [value] for [property] on [element], tried on
/// the element's own kind for a shape attribute that applies to it, and on a
/// group for any other, which every element reads alike. Only kinds
/// flutter_svg draws are tried: it reports any other from an assert, which
/// would make the answer differ between debug and release builds.
bool _passes(
  ValueCheck check,
  String property,
  String value,
  XmlElement element,
) =>
    check.passes(
      _shapeAttributes[property]?.contains(element.localName) ?? false
          ? element.localName
          : 'g',
      property,
      value,
    );

/// The `transform-origin` [element]'s CSS transform turns about, with
/// variables resolved: from a rule, its own style or its attribute, `0 0`
/// when none is set. Null for a `transform-box` other than the default
/// `view-box`, which places the origin relative to the shape's bounds, and
/// for an origin whose variables cannot be resolved.
String? _transformOrigin(
  XmlElement element,
  Map<String, _Declaration> declarations,
  _Variables variables,
) {
  if (declarations['transform-box'] case final box?) {
    if (variables.resolve(box.value, element)?.trim() != 'view-box') {
      return null;
    }
  }
  return switch (declarations['transform-origin']) {
    final declaration? => variables.resolve(declaration.value, element),
    null => element.getAttribute('transform-origin') ?? '0 0',
  };
}

/// The shape attributes CSS can set, each with the elements it applies to.
/// flutter_svg reads a `style` declaration as it reads the attribute. An
/// `image`'s are left out: flutter_svg reads its `x` and `y` only as plain
/// numbers and throws on a unit, and ignores a `width` or `height` with one.
const _shapeAttributes = {
  'cx': {'circle', 'ellipse'},
  'cy': {'circle', 'ellipse'},
  'r': {'circle'},
  'rx': {'rect', 'ellipse'},
  'ry': {'rect', 'ellipse'},
  'x': {'rect'},
  'y': {'rect'},
  'width': {'rect'},
  'height': {'rect'},
};

/// Resolves `var()` against the custom properties the cascade gave each
/// element. A custom property is read on the element or its nearest
/// ancestor that sets it, and the variables in its value are resolved there.
class _Variables {
  _Variables(this._styled, this._maxLength);

  /// The `var()` substitutions resolving one value may take: a loop of
  /// references, or variables that each use the one before several times,
  /// run out of them rather than stall the app.
  static const _maxSubstitutions = 256;

  /// Every element with a declaration: one a rule gave it, or its own.
  final Map<XmlElement, Map<String, _Declaration>> _styled;

  /// Longer than this, the SVG's own length, a value is taken to be invalid:
  /// each substitution can copy a long value, and the budget alone would let
  /// a value grow hundreds of times the SVG's size.
  final int _maxLength;

  var _substitutionsLeft = 0;

  // Remembered per element from its parent's, so each element is looked at
  // once per name rather than walked up from on every use.
  final _declared = <(XmlElement, String), (XmlElement, _Declaration)?>{};

  /// [value] with each `var(--name)` or `var(--name, fallback)` replaced by
  /// the value of `--name` at [element], or by its fallback where it is not
  /// set or cannot be resolved; null where neither can be, where a `var()`
  /// is unclosed, where it needs more than [_maxSubstitutions], or where it
  /// grows longer than [_maxLength].
  String? resolve(String value, XmlElement element) {
    _substitutionsLeft = _maxSubstitutions;
    return _substitute(value, element);
  }

  String? _substitute(String value, XmlElement element) {
    final out = StringBuffer();
    var rest = value;
    for (var match = _variable.firstMatch(rest);
        match != null;
        match = _variable.firstMatch(rest)) {
      if (--_substitutionsLeft < 0) return null;
      final close = _closingParenthesis(rest, match.end);
      if (close < 0) return null;
      final inner = rest.substring(match.end, close);
      final comma = inner.indexOf(',');
      final name = (comma < 0 ? inner : inner.substring(0, comma)).trim();
      final replacement = _valueOf(name, element) ??
          (comma < 0
              ? null
              : _substitute(inner.substring(comma + 1).trim(), element));
      if (replacement == null) return null;
      out
        ..write(rest.substring(0, match.start))
        ..write(replacement);
      if (out.length > _maxLength) return null;
      rest = rest.substring(close + 1);
    }
    return (out..write(rest)).toString();
  }

  String? _valueOf(String name, XmlElement element) {
    if (_declaring(name, element) case (final at, final declaration)) {
      return _substitute(declaration.value, at);
    }
    return null;
  }

  /// The element that sets [name] for [element], itself or its nearest
  /// ancestor, with its declaration; null where none does.
  (XmlElement, _Declaration)? _declaring(String name, XmlElement element) {
    final key = (element, name);
    if (_declared.containsKey(key)) return _declared[key];
    final parent = element.parentElement;
    return _declared[key] = switch (_styled[element]?[name]) {
      final declaration? => (element, declaration),
      null => parent == null ? null : _declaring(name, parent),
    };
  }
}

/// The index of the `)` closing the parenthesis opened before [start] in
/// [text], skipping quoted text and nested parentheses; -1 if it is not
/// closed.
int _closingParenthesis(String text, int start) {
  var depth = 1;
  String? quote;
  for (var i = start; i < text.length; i++) {
    final char = text[i];
    if (quote != null) {
      if (char == quote) quote = null;
    } else if (char == '"' || char == "'") {
      quote = char;
    } else if (char == '(') {
      depth++;
    } else if (char == ')' && --depth == 0) {
      return i;
    }
  }
  return -1;
}

class _Rule {
  _Rule(this.selector, this.specificity, this.order, this.declarations);

  final String selector;
  final int specificity;
  final int order;

  /// Shared by every selector of one rule set; each is placed in the cascade
  /// with [inRule] only where it applies.
  final List<_Declaration> declarations;
}

class _Declaration {
  _Declaration(
    this.property,
    this.value, {
    required this.important,
    required this.own,
    this.specificity = 0,
    this.order = 0,
  });

  final String property;
  final String value;
  final bool important;

  /// Whether it comes from the element's own `style` attribute.
  final bool own;
  final int specificity;
  final int order;

  /// This declaration as [rule]'s, at its specificity and order.
  _Declaration inRule(_Rule rule) => _Declaration(
        property,
        value,
        important: important,
        own: false,
        specificity: rule.specificity,
        order: rule.order,
      );

  bool beats(_Declaration other) {
    if (important != other.important) return important;
    if (own != other.own) return own;
    if (specificity != other.specificity) {
      return specificity > other.specificity;
    }
    return order > other.order;
  }
}

/// One rule per matchable selector of every sheet in [sheets] that sets a
/// taken property, in source order.
List<_Rule> _rules(List<XmlElement> sheets) {
  final rules = <_Rule>[];
  for (final style in sheets) {
    final sheet = css.parse(style.innerText, errors: []);
    for (final ruleSet in sheet.topLevels.whereType<css.RuleSet>()) {
      final declarations = _ruleDeclarations(ruleSet);
      if (declarations.isEmpty) continue;
      for (final selector in ruleSet.selectorGroup?.selectors ?? const []) {
        final text = selector.span?.text.trim() ?? '';
        if (text.isEmpty || !_matchable(selector)) continue;
        rules.add(
          _Rule(text, _specificity(selector), rules.length, declarations),
        );
      }
    }
  }
  return rules;
}

/// The taken declarations of [ruleSet], read once for all its selectors. Of
/// two declarations of a property, the later one wins unless only the
/// earlier one is !important.
List<_Declaration> _ruleDeclarations(css.RuleSet ruleSet) {
  final declarations = <String, _Declaration>{};
  for (final d
      in ruleSet.declarationGroup.declarations.whereType<css.Declaration>()) {
    // Read from the declaration's source text, because csslib's expression
    // span stops at a function name and would turn hsl(...) into "hsl".
    for (final declaration in _declarationsIn(d.span.text, own: false)) {
      if (_taken(declaration.property)) _keep(declarations, declaration);
    }
  }
  return declarations.values.toList();
}

/// The pseudo-classes matched as CSS defines them: `:root` through the
/// [_Mirror]'s mark, the others by package:html. package:html evaluates
/// others wrongly (`:nth-child` counts from 0, `:empty` is inverted, `:link`
/// takes any element with an `href`), so a selector using one is skipped
/// rather than misapplied.
const _matchablePseudoClasses = {
  'first-child',
  'last-child',
  'only-child',
  'root',
};

// The ~ combinator is skipped too: package:html's costs the cube of the
// number of siblings, seconds for a few thousand shapes.
bool _matchable(css.Selector selector) =>
    selector.simpleSelectorSequences.every(
      (sequence) =>
          !sequence.isCombinatorTilde &&
          _matchableSimple(sequence.simpleSelector),
    );

bool _matchableSimple(css.SimpleSelector selector) => switch (selector) {
      css.PseudoClassSelector(:final name) =>
        _matchablePseudoClasses.contains(name),
      css.PseudoElementSelector() => false,
      css.NegationSelector(:final negationArg?) =>
        _matchableSimple(negationArg),
      css.NegationSelector() => false,
      _ => true,
    };

/// The declarations written as [text] (`property: value`, optionally
/// `!important`): one, or a `font` shorthand's longhands (see
/// [fontLonghands]). None when it has no property or no value, or is a
/// shorthand that cannot be expanded.
List<_Declaration> _declarationsIn(String text, {required bool own}) {
  final colon = text.indexOf(':');
  if (colon < 0) return const [];
  final property = text.substring(0, colon).trim();
  final rest = text.substring(colon + 1);
  final value = rest.replaceFirst(_important, '').trim();
  if (property.isEmpty || value.isEmpty) return const [];
  final longhands =
      property == 'font' ? fontLonghands(value) : {property: value};
  return [
    for (final MapEntry(:key, :value) in longhands?.entries ?? const [])
      _Declaration(
        key,
        value,
        important: _important.hasMatch(rest),
        own: own,
      ),
  ];
}

/// Ids, then classes, attributes and pseudo-classes, then types, packed so a
/// larger number is more specific. `:not` weighs as its argument.
int _specificity(css.Selector selector) => selector.simpleSelectorSequences
    .map((sequence) => _weight(sequence.simpleSelector))
    .fold(0, (sum, weight) => sum + weight);

int _weight(css.SimpleSelector selector) => switch (selector) {
      css.IdSelector() => 1000000,
      css.ClassSelector() ||
      css.AttributeSelector() ||
      css.PseudoClassSelector() =>
        1000,
      css.ElementSelector(isWildcard: false) => 1,
      css.NegationSelector(:final negationArg?) => _weight(negationArg),
      _ => 0,
    };

// Split at every `;`, as flutter_svg splits a style, so a value holding a
// `;` is read as flutter_svg reads it.
Map<String, _Declaration> _ownDeclarations(XmlElement element) {
  final declarations = <String, _Declaration>{};
  for (final text in (element.getAttribute('style') ?? '').split(';')) {
    for (final declaration in _declarationsIn(text, own: true)) {
      _keep(declarations, declaration);
    }
  }
  return declarations;
}

/// Puts [declaration] in [declarations] unless an earlier one of its
/// property beats it: in one rule or one style, the later declaration wins
/// unless only the earlier one is !important.
void _keep(
  Map<String, _Declaration> declarations,
  _Declaration declaration,
) {
  final earlier = declarations[declaration.property];
  if (earlier == null || !earlier.beats(declaration)) {
    declarations[declaration.property] = declaration;
  }
}
