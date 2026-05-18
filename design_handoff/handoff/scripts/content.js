/* Soliplex Design System — content */
/* Injects all section markup into <main id="main"> */

const LIGHT_TOKENS = [
  ["background","#ffffff"],["foreground","#0A0A0A"],
  ["primary","#030213"],["onPrimary","#ffffff"],
  ["primaryContainer","#E0DDDA"],["onPrimaryContainer","#0A0A0A"],
  ["secondary","#F3F3FA"],["onSecondary","#030213"],
  ["tertiary","#6B7280"],["onTertiary","#FFFFFF"],
  ["tertiaryContainer","#F3F4F6"],["onTertiaryContainer","#374151"],
  ["accent","#E9EBEF"],["onAccent","#030213"],
  ["muted","#ECECF0"],["mutedForeground","#595968"],
  ["destructive","#D4183D"],["onDestructive","#ffffff"],
  ["errorContainer","#FEE2E2"],["onErrorContainer","#991B1B"],
  ["border","rgba(0,0,0,0.10)"],["outline","#C0C0C4"],["outlineVariant","#E0E0E2"],
  ["inputBackground","#F3F3F5"],["hintText","#666666"],
  ["surfaceContainerLowest","#FFFFFF"],["surfaceContainerLow","#EFEFEF"],
  ["surfaceContainerHigh","#ECECEC"],["surfaceContainerHighest","#E4E4E4"],
  ["inversePrimary","#B0B0B0"],["link","#2563EB"],
];
const DARK_TOKENS = [
  ["background","#111111"],["foreground","#FAFAFA"],
  ["primary","#FAFAFA"],["onPrimary","#222222"],
  ["primaryContainer","#2A2A2A"],["onPrimaryContainer","#FAFAFA"],
  ["secondary","#2A2A2A"],["onSecondary","#FFFFFF"],
  ["tertiary","#9CA3AF"],["onTertiary","#1F1F1F"],
  ["tertiaryContainer","#2A2A2A"],["onTertiaryContainer","#D1D5DB"],
  ["accent","#2A2A2A"],["onAccent","#FFFFFF"],
  ["muted","#444444"],["mutedForeground","#AAAAAA"],
  ["destructive","#D4183D"],["onDestructive","#FFFFFF"],
  ["errorContainer","#3D1A1A"],["onErrorContainer","#FCA5A5"],
  ["border","#2A2A2A"],["outline","#555555"],["outlineVariant","#3A3A3A"],
  ["inputBackground","#333333"],["hintText","#A3A3A3"],
  ["surfaceContainerLowest","#0E0E0E"],["surfaceContainerLow","#1A1A1A"],
  ["surfaceContainerHigh","#2A2A2A"],["surfaceContainerHighest","#333333"],
  ["inversePrimary","#555555"],["link","#60A5FA"],
];

function tokenTable(rows) {
  const body = rows.map(([name, hex]) => `
    <tr>
      <td><span class="swatch" style="background:${hex}"></span><span class="name">${name}</span></td>
      <td><code>${hex}</code></td>
    </tr>`).join("");
  return `<table class="token-table"><thead><tr><th>Token</th><th>Value</th></tr></thead><tbody>${body}</tbody></table>`;
}

function codeBlock(lang, label, code) {
  const esc = code.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
  return `<div class="code-block"><div class="code-head"><span>${label}</span><span>${lang}</span></div><pre>${esc}</pre></div>`;
}

/* =================== SECTIONS =================== */

const overview = `
<section id="overview">
  <div class="kicker">Soliplex Frontend · v0.83.1</div>
  <h1>Design System</h1>
  <p class="lede">
    Soliplex is an agentic interface to third-party backend LLMs running over
    datasets ingested by Soliplex. This guide documents the tokens, themes,
    and components used across the Flutter frontend &mdash; extracted
    directly from <code>lib/src/design/</code>.
  </p>

  <div class="callout">
    <strong>Single source of truth.</strong> Every token and component on this
    page maps 1:1 to code in <code>soliplex/frontend</code>.
    Dart snippets show exactly what shipped. When the code changes, this doc
    should change with it.
  </div>

  <h3>What's in scope</h3>
  <p>
    The frontend is a modular Flutter shell composed of five feature modules
    (<em>auth</em>, <em>lobby</em>, <em>room</em>, <em>quiz</em>, <em>diagnostics</em>)
    targeting Android, iOS, macOS, Linux, Windows, and the web. Material 3 is the
    base; a <code>SoliplexTheme</code> extension layers brand tokens on top.
  </p>

  ${codeBlock("dart", "lib/src/design/design.dart", `export 'color/color_scheme_extensions.dart';
export 'theme/theme.dart';
export 'theme/theme_extensions.dart';
export 'tokens/breakpoints.dart';
export 'tokens/colors.dart';
export 'tokens/radii.dart';
export 'tokens/spacing.dart';
export 'tokens/typography.dart';
export 'tokens/typography_x.dart';`)}
</section>`;

const brand = `
<section id="brand">
  <h2>Brand</h2>
  <p class="lede">
    The Soliplex mark is a set of three concentric cyan rings crossed by four
    axial bars, anchored on a diamond. It reads as a target, a compass, and
    a dataset grid &mdash; three metaphors that map to the product: focus,
    retrieval, structure.
  </p>

  <div class="brand-strip">
    <div class="brand-tile dark">
      <img src="assets/branding/soliplex/logo.svg" alt="Soliplex logo" style="width:96px;height:96px;" />
      <div class="label">logo.svg · full mark</div>
    </div>
    <div class="brand-tile">
      <img src="assets/branding/soliplex/logo_1024.png" alt="Soliplex logo (raster)" style="width:96px;height:96px;" />
      <div class="label">logo_1024.png · splash &amp; launcher</div>
    </div>
    <div class="brand-tile">
      <div style="width:64px;height:64px;border-radius:14px;background:#424242;margin:0 auto;display:flex;align-items:center;justify-content:center;">
        <img src="assets/branding/soliplex/favicon_48.png" alt="" style="width:32px;height:32px;" />
      </div>
      <div class="label">favicon_48.png · web tab</div>
    </div>
  </div>

  <h3>Brand palette</h3>
  <p>Used exclusively in the mark &mdash; not in the UI chrome.</p>
  <div class="swatch-grid">
    <div class="sw-card"><div class="fill" style="background:#2F3337"></div><div class="meta"><div class="name">mark/background</div><div class="hex">#2F3337</div></div></div>
    <div class="sw-card"><div class="fill" style="background:#60C7D8"></div><div class="meta"><div class="name">mark/ring</div><div class="hex">#60C7D8</div></div></div>
    <div class="sw-card"><div class="fill" style="background:#333335"></div><div class="meta"><div class="name">mark/bar</div><div class="hex">#333335</div></div></div>
    <div class="sw-card"><div class="fill" style="background:#E6F1F3"></div><div class="meta"><div class="name">mark/diamond</div><div class="hex">#E6F1F3</div></div></div>
  </div>

  <h3>Splash &amp; launcher</h3>
  ${codeBlock("yaml", "pubspec.yaml", `flutter_launcher_icons:
  android: true
  ios: true
  macos:
    generate: true
  web:
    generate: true
  image_path: "assets/branding/soliplex/app_icon_1024.png"
  adaptive_icon_background: "#424242"
  adaptive_icon_foreground: "assets/branding/soliplex/logo_1024.png"
  web_favicon_path: "assets/branding/soliplex/favicon_48.png"

flutter_native_splash:
  color: "#424242"
  image: assets/branding/soliplex/logo_1024.png`)}
</section>`;

const color = `
<section id="color">
  <h2>Color</h2>
  <p class="lede">
    Colors are declared as a <code>SoliplexColors</code> record in
    <code>lib/src/design/tokens/colors.dart</code>, then mapped into Flutter's
    <code>ColorScheme</code> by <code>soliplexLightTheme</code>. Two constant
    palettes ship: <code>lightSoliplexColors</code> and
    <code>darkSoliplexColors</code>.
  </p>

  <h3>Light palette</h3>
  <div class="swatch-grid">
    ${LIGHT_TOKENS.slice(0, 12).map(([n, h]) => `
      <div class="sw-card"><div class="fill" style="background:${h}"></div>
      <div class="meta"><div class="name">${n}</div><div class="hex">${h}</div></div></div>`).join("")}
  </div>
  <details class="mt-2"><summary class="muted small" style="cursor:pointer;">Show all 31 light tokens</summary>
    ${tokenTable(LIGHT_TOKENS)}
  </details>

  <h3>Dark palette</h3>
  <div class="swatch-grid">
    ${DARK_TOKENS.slice(0, 12).map(([n, h]) => `
      <div class="sw-card"><div class="fill" style="background:${h}"></div>
      <div class="meta"><div class="name">${n}</div><div class="hex">${h}</div></div></div>`).join("")}
  </div>
  <details class="mt-2"><summary class="muted small" style="cursor:pointer;">Show all 31 dark tokens</summary>
    ${tokenTable(DARK_TOKENS)}
  </details>

  <h3>Usage guidelines</h3>
  <ul>
    <li><strong>primary / onPrimary</strong> &mdash; CTA fills, selected tiles, focus rings.</li>
    <li><strong>primaryContainer</strong> &mdash; user message bubbles and emphasised surfaces.</li>
    <li><strong>surfaceContainerLow / High / Highest</strong> &mdash; elevation without shadows. Layer surfaces on a flat theme by bumping the container level.</li>
    <li><strong>inputBackground</strong> &mdash; default <code>fillColor</code> for all <code>TextField</code>s; also reused as the default <code>Card</code> background and the selected <code>ListTile</code> fill.</li>
    <li><strong>border</strong> is 10% black in light and <code>#2A2A2A</code> in dark &mdash; 1px hairlines across buttons, inputs, expansion tiles, and the app bar bottom edge.</li>
    <li><strong>destructive / errorContainer</strong> &mdash; reserved for destructive actions and validation failures. Never decorate.</li>
    <li><strong>link</strong> &mdash; only for markdown rendering; do not use for UI actions (use a <code>TextButton</code> instead).</li>
  </ul>

  ${codeBlock("dart", "lib/src/design/tokens/colors.dart", `const lightSoliplexColors = SoliplexColors(
  background: Color(0xffffffff),
  foreground: Color(0xFF0A0A0A),
  primary: Color(0xFF030213),
  onPrimary: Color(0xffffffff),
  primaryContainer: Color(0xFFE0DDDA),
  onPrimaryContainer: Color(0xFF0A0A0A),
  // …full record has 31 fields
);`)}

  ${codeBlock("dart", "color_scheme_extensions.dart · symbolic colors", `extension SymbolicColors on ColorScheme {
  bool get isDarkMode => brightness == Brightness.dark;

  Color get info    => brightness == Brightness.light ? Colors.blue   : Colors.blue.shade300;
  Color get warning => brightness == Brightness.light ? Colors.orange : Colors.orange.shade300;
  Color get danger  => brightness == Brightness.light ? Colors.red    : Colors.red.shade300;
  Color get success => brightness == Brightness.light ? Colors.green  : Colors.green.shade300;
}`)}
</section>`;

window.__SECTIONS_1 = { overview, brand, color };
