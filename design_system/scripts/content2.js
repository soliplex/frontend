/* Soliplex Design System — content part 2: typography, spacing, radii, breakpoints, components, engineering */

const typography = `
<section id="typography">
  <h2>Typography</h2>
  <p class="lede">
    One function &mdash; <code>soliplexTextTheme(SoliplexColors)</code> &mdash;
    produces Flutter's <code>TextTheme</code>. All sizes use
    <code>height: 1.5</code> except the display style which uses 1.3. No custom
    font family is bundled; platforms render in their native sans
    (Roboto on Android, SF on iOS/macOS, system default elsewhere). The
    monospace style resolves to SF&nbsp;Mono on Cupertino and Roboto Mono everywhere
    else.
  </p>

  <div class="theme-demo">
    <div class="panel">
      <div style="font-size:28px;font-weight:400;line-height:1.3;margin-bottom:14px;">Headline medium &mdash; the quick brown fox</div>
      <div style="font-size:24px;font-weight:500;line-height:1.5;margin-bottom:10px;">Title large &mdash; room overview</div>
      <div style="font-size:20px;font-weight:500;line-height:1.5;margin-bottom:10px;">Title medium &mdash; thread details</div>
      <div style="font-size:16px;font-weight:500;line-height:1.5;margin-bottom:10px;">Title small &mdash; message author</div>
      <div style="font-size:18px;font-weight:400;line-height:1.5;margin-bottom:10px;">Body large &mdash; long-form markdown output from the agent.</div>
      <div style="font-size:16px;font-weight:400;line-height:1.5;margin-bottom:10px;">Body medium &mdash; default UI text size across lists, cards, and dialogs.</div>
      <div style="font-size:13px;font-weight:400;line-height:1.5;margin-bottom:10px;color:#595968;">Body small &mdash; metadata, timestamps, helper text.</div>
      <div style="font-size:16px;font-weight:500;line-height:1.5;margin-bottom:10px;">Label medium &mdash; buttons, tabs</div>
      <div style="font-size:12px;font-weight:500;line-height:1.5;letter-spacing:0.02em;color:#595968;">LABEL SMALL &mdash; CHIPS, BADGES</div>
    </div>
  </div>

  <table class="token-table">
    <thead><tr><th>Style</th><th>Size</th><th>Weight</th><th>Line height</th><th>Use for</th></tr></thead>
    <tbody>
      <tr><td><span class="name">headlineMedium</span></td><td><code>28</code></td><td>w400</td><td><code>1.3</code></td><td>Top-of-screen titles</td></tr>
      <tr><td><span class="name">titleLarge</span></td><td><code>24</code></td><td>w500</td><td><code>1.5</code></td><td>Markdown H1, section titles</td></tr>
      <tr><td><span class="name">titleMedium</span></td><td><code>20</code></td><td>w500</td><td><code>1.5</code></td><td>Markdown H2, dialog headings</td></tr>
      <tr><td><span class="name">titleSmall</span></td><td><code>16</code></td><td>w500</td><td><code>1.5</code></td><td>Markdown H3, list titles</td></tr>
      <tr><td><span class="name">bodyLarge</span></td><td><code>18</code></td><td>w400</td><td><code>1.5</code></td><td>Markdown body in messages</td></tr>
      <tr><td><span class="name">bodyMedium</span></td><td><code>16</code></td><td>w400</td><td><code>1.5</code></td><td>Default UI body</td></tr>
      <tr><td><span class="name">bodySmall</span></td><td><code>13</code></td><td>w400</td><td><code>1.5</code></td><td>Helper text, metadata</td></tr>
      <tr><td><span class="name">labelMedium</span></td><td><code>16</code></td><td>w500</td><td><code>1.5</code></td><td>Button labels</td></tr>
      <tr><td><span class="name">labelSmall</span></td><td><code>12</code></td><td>w500</td><td><code>1.5</code></td><td>Chip labels, timestamps</td></tr>
    </tbody>
  </table>

  <h3>Monospace</h3>
  <p>Used for code blocks, inline code spans, and the network inspector. Reads from the platform via a helper so iOS/macOS get SF Mono automatically.</p>

  ${codeBlock("dart", "lib/src/design/tokens/typography_x.dart", `TextStyle appMonospaceTextStyle(BuildContext context) {
  final base = Theme.of(context).textTheme.bodyMedium;

  if (isCupertino(context)) {
    return base!.copyWith(
      fontFamily: 'SF Mono',
      fontFamilyFallback: const ['Menlo', 'monospace'],
    );
  }

  return base!.copyWith(
    fontFamily: 'Roboto Mono',
    fontFamilyFallback: const ['monospace'],
  );
}

extension TypographyX on BuildContext {
  TextStyle get monospace => appMonospaceTextStyle(this);
}`)}
</section>`;

const spacing = `
<section id="spacing">
  <h2>Spacing</h2>
  <p class="lede">
    Soliplex ships a deliberately tiny spacing scale &mdash; five values,
    4&nbsp;px to 24&nbsp;px. Any larger gap is expressed as a multiple of these
    in page code. There is no <code>s5</code> because it was never needed;
    add with discipline if a new value is genuinely missing.
  </p>

  <div class="theme-demo">
    <div class="panel">
      <div class="ruler-row"><span class="ruler-label">s1</span><span class="ruler-val">4px</span><div class="ruler-bar" style="width:4px"></div></div>
      <div class="ruler-row"><span class="ruler-label">s2</span><span class="ruler-val">8px</span><div class="ruler-bar" style="width:8px"></div></div>
      <div class="ruler-row"><span class="ruler-label">s3</span><span class="ruler-val">12px</span><div class="ruler-bar" style="width:12px"></div></div>
      <div class="ruler-row"><span class="ruler-label">s4</span><span class="ruler-val">16px</span><div class="ruler-bar" style="width:16px"></div></div>
      <div class="ruler-row"><span class="ruler-label">s6</span><span class="ruler-val">24px</span><div class="ruler-bar" style="width:24px"></div></div>
    </div>
  </div>

  ${codeBlock("dart", "lib/src/design/tokens/spacing.dart", `class SoliplexSpacing {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s6 = 24;
}`)}

  <div class="callout">
    <strong>Padding conventions.</strong> Chat bubbles use <code>14/10</code>,
    the chat input wrapper uses an <code>EdgeInsets.all(8)</code>. The app
    bar's actions use <code>symmetric(horizontal: s2)</code>. Chips use
    <code>symmetric(horizontal: s2, vertical: s1)</code>.
  </div>
</section>`;

const radii = `
<section id="radii">
  <h2>Radii</h2>
  <p class="lede">
    Corner radii come from <code>SoliplexRadii</code>, a
    <code>ThemeExtension</code>-aware type so radii can be interpolated
    during theme transitions. <code>md</code> is the default for almost every
    control. Reserve <code>sm</code> for checkboxes and hit-target wells.
  </p>

  <div class="theme-demo">
    <div class="panel" style="display:flex;gap:20px;flex-wrap:wrap;">
      <div style="text-align:center;"><div style="width:96px;height:96px;background:var(--doc-subtle);border:1px solid var(--doc-border-strong);border-radius:6px;"></div><div class="small muted mt-2 mono">sm · 6</div></div>
      <div style="text-align:center;"><div style="width:96px;height:96px;background:var(--doc-subtle);border:1px solid var(--doc-border-strong);border-radius:12px;"></div><div class="small muted mt-2 mono">md · 12 (default)</div></div>
      <div style="text-align:center;"><div style="width:96px;height:96px;background:var(--doc-subtle);border:1px solid var(--doc-border-strong);border-radius:16px;"></div><div class="small muted mt-2 mono">lg · 16</div></div>
      <div style="text-align:center;"><div style="width:96px;height:96px;background:var(--doc-subtle);border:1px solid var(--doc-border-strong);border-radius:24px;"></div><div class="small muted mt-2 mono">xl · 24</div></div>
    </div>
  </div>

  ${codeBlock("dart", "lib/src/design/tokens/radii.dart", `class SoliplexRadii {
  const SoliplexRadii({
    required this.sm, required this.md, required this.lg, required this.xl,
  });

  factory SoliplexRadii.lerp(SoliplexRadii a, SoliplexRadii b, double t) =>
      SoliplexRadii(
        sm: lerpDouble(a.sm, b.sm, t)!,
        md: lerpDouble(a.md, b.md, t)!,
        lg: lerpDouble(a.lg, b.lg, t)!,
        xl: lerpDouble(a.xl, b.xl, t)!,
      );

  final double sm; final double md; final double lg; final double xl;
}

const soliplexRadii = SoliplexRadii(sm: 6, md: 12, lg: 16, xl: 24);`)}
</section>`;

const breakpoints = `
<section id="breakpoints">
  <h2>Breakpoints</h2>
  <p class="lede">
    The lobby and room shells swap between wide and narrow layouts at these
    widths. The tablet/desktop boundary is where the sidebar
    becomes persistent instead of a drawer.
  </p>

  <table class="token-table">
    <thead><tr><th>Name</th><th>Width</th><th>Layout</th></tr></thead>
    <tbody>
      <tr><td><span class="name">mobile</span></td><td><code>≥ 320</code></td><td>Single column, drawer nav</td></tr>
      <tr><td><span class="name">tablet</span></td><td><code>≥ 600</code></td><td>Two columns; master/detail</td></tr>
      <tr><td><span class="name">desktop</span></td><td><code>≥ 840</code></td><td>Persistent sidebar + main + detail</td></tr>
    </tbody>
  </table>

  ${codeBlock("dart", "lib/src/design/tokens/breakpoints.dart", `class SoliplexBreakpoints {
  static const double desktop = 840;
  static const double tablet = 600;
  static const double mobile = 320;
}`)}
</section>`;

const componentsIntro = `
<section id="components">
  <h2>Components</h2>
  <p class="lede">
    Soliplex keeps its widget surface small. Nothing here is a bespoke render
    tree &mdash; every control below is either Material 3 with
    <code>ThemeData</code> overrides, or a small composition on top. The
    previews render the real CSS values pulled from the tokens, and can
    toggle between the shipped Light and Dark themes.
  </p>
  <div class="callout">
    <strong>Tip.</strong> Use the tabs above each component preview to switch
    between the <code>lightSoliplexColors</code> and
    <code>darkSoliplexColors</code> palettes. The values are wired to the
    real exported Dart tokens.
  </div>
</section>`;

function demoBlock(id, title, demoHtml, dartLabel, dart) {
  return `
<section id="${id}">
  <h3>${title}</h3>
  <div class="theme-demo" data-mode="light">
    <div class="tabs">
      <button class="active" data-set="light">Light</button>
      <button data-set="dark">Dark</button>
    </div>
    <div class="panel">
      <div class="demo-surface" data-demo-mode="light">${demoHtml}</div>
      <div class="demo-surface" data-demo-mode="dark">${demoHtml}</div>
    </div>
  </div>
  ${codeBlock("dart", dartLabel, dart)}
</section>`;
}

const buttonsDemo = `
  <div class="demo-row">
    <button class="m-btn m-btn-filled">Send message</button>
    <button class="m-btn m-btn-outlined">Cancel</button>
    <button class="m-btn m-btn-text">Learn more</button>
    <button class="m-btn m-btn-destructive">Delete server</button>
    <button class="m-icon-btn" aria-label="Attach">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48"/></svg>
    </button>
  </div>`;

const buttons = demoBlock("buttons", "Buttons",
  buttonsDemo,
  "lib/src/design/theme/theme.dart · filled &amp; outlined button themes",
  `filledButtonTheme: FilledButtonThemeData(
  style: FilledButton.styleFrom(
    shape: RoundedRectangleBorder(
      side: BorderSide(color: colors.border),
      borderRadius: BorderRadius.circular(soliplexRadii.md),
    ),
  ),
),
outlinedButtonTheme: OutlinedButtonThemeData(
  style: OutlinedButton.styleFrom(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(soliplexRadii.md),
    ),
    side: BorderSide(color: colors.border),
  ),
),`
);

const inputsDemo = `
  <div class="demo-col">
    <input class="m-input" placeholder="Type a message..." />
    <input class="m-input" value="http://localhost:8000" />
    <div class="demo-row">
      <input class="m-input" placeholder="Email" style="flex:1" />
      <input class="m-input" placeholder="Password" type="password" style="flex:1" />
    </div>
    <div class="small" style="color:var(--c-muted-fg);">Hint text sits below the field with a <code>bodySmall</code> style.</div>
  </div>`;

const inputs = demoBlock("inputs", "Inputs",
  inputsDemo,
  "lib/src/design/theme/theme.dart · inputDecorationTheme (excerpt)",
  `inputDecorationTheme: InputDecorationTheme(
  filled: true,
  fillColor: colors.inputBackground,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(soliplexRadii.md),
    borderSide: BorderSide.none,
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(soliplexRadii.md),
    borderSide: BorderSide(color: colors.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(soliplexRadii.md),
    borderSide: BorderSide(color: colors.border, width: 2),
  ),
  errorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(soliplexRadii.md),
    borderSide: BorderSide(color: colors.destructive),
  ),
  hintStyle: TextStyle(color: colors.hintText),
),`
);

const cardsDemo = `
  <div class="m-card" style="margin-bottom:12px;">
    <div class="m-list-tile">
      <div style="flex:1;">
        <div class="title">Medical RAG · production</div>
        <div class="subtitle">Responds over the clinical guidelines corpus</div>
      </div>
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 11V7a3 3 0 0 1 6 0v4"/><rect x="5" y="11" width="14" height="10" rx="2"/></svg>
      <button class="m-icon-btn" aria-label="Info">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>
      </button>
    </div>
  </div>
  <div class="m-card">
    <div class="m-list-tile">
      <div style="flex:1;">
        <div class="title">Ops playbooks</div>
        <div class="subtitle">Internal runbooks &amp; postmortems</div>
      </div>
      <button class="m-icon-btn" aria-label="Info">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>
      </button>
    </div>
  </div>`;

const cards = demoBlock("cards", "Cards &amp; List Tiles",
  cardsDemo,
  "lib/src/modules/lobby/ui/room_card.dart",
  `class RoomCard extends StatelessWidget {
  const RoomCard({
    super.key,
    required this.room,
    required this.onTap,
    required this.onInfoTap,
  });

  final Room room;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(room.name),
        subtitle: room.description.isNotEmpty ? Text(room.description) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (room.hasQuizzes)
              Tooltip(
                message: 'Has quizzes',
                child: Icon(Icons.quiz, size: 20, color: Theme.of(context).colorScheme.primary),
              ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: onInfoTap,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}`
);

const chipsDemo = `
  <div class="demo-row">
    <span class="m-chip">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
      guidelines.pdf
      <span class="x" aria-label="Remove">×</span>
    </span>
    <span class="m-chip selected">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
      triage-protocol.md
      <span class="x">×</span>
    </span>
    <span class="m-chip">filter · open</span>
    <span class="m-badge">RAG</span>
    <span class="m-badge">streaming</span>
  </div>
  <p class="small mt-3" style="color:var(--c-muted-fg);">Chips show selected documents in the chat input. Badges are the SoliplexBadgeThemeData extension &mdash; used for execution-step labels.</p>`;

const chips = demoBlock("chips", "Chips &amp; Badges",
  chipsDemo,
  "lib/src/design/theme/theme.dart · chipTheme &amp; SoliplexBadgeThemeData",
  `chipTheme: ChipThemeData(
  backgroundColor: colors.inputBackground,
  selectedColor: colors.primary.withAlpha(25),
  disabledColor: colors.muted,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(soliplexRadii.md),
    side: BorderSide(color: colors.border),
  ),
  padding: const EdgeInsets.symmetric(
    horizontal: SoliplexSpacing.s2,
    vertical: SoliplexSpacing.s1,
  ),
),

// SoliplexBadgeThemeData — lib/src/design/theme/theme_extensions.dart
SoliplexBadgeThemeData(
  background: Color.alphaBlend(
    colors.foreground.withAlpha(15),
    colors.background,
  ),
  textStyle: textTheme.labelMedium!.copyWith(color: colors.foreground),
  padding: const EdgeInsets.symmetric(
    horizontal: SoliplexSpacing.s2,
    vertical: SoliplexSpacing.s1,
  ),
),`
);

const chatDemo = `
  <div class="demo-col" style="gap:10px;">
    <div style="font-size:12px;font-weight:500;color:var(--c-muted-fg);">You</div>
    <div class="m-msg-bubble user">What's the recommended dose of amoxicillin for a 22 kg child with acute otitis media?</div>
    <div style="font-size:12px;font-weight:500;color:var(--c-muted-fg);margin-top:8px;">Assistant</div>
    <div class="m-msg-bubble assistant">
      <div style="font-size:12px;color:var(--c-muted-fg);margin-bottom:4px;">Thinking… <span style="font-style:italic;">retrieving 4 passages</span></div>
      For a 22 kg child, the guideline recommends <strong>80–90 mg/kg/day</strong>
      of amoxicillin divided BID, so roughly <strong>880 mg twice daily</strong> for 10 days.
      <div style="margin-top:10px;padding-top:8px;border-top:1px solid var(--c-border);font-size:12px;color:var(--c-muted-fg);">Sources · 2 citations</div>
    </div>
  </div>`;

const chat = demoBlock("chat", "Chat &amp; Messages",
  chatDemo,
  "lib/src/modules/room/ui/text_message_tile.dart (excerpt)",
  `Container(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  decoration: BoxDecoration(
    color: isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(12),
  ),
  child: isUser
      ? SelectableText(
          message.text,
          style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
        )
      : message.text.isEmpty
          ? const Text('...')
          : FlutterMarkdownPlusRenderer(data: message.text),
),`
);

const feedbackDemo = `
  <div class="demo-row">
    <button class="m-icon-btn" aria-label="Thumbs up">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M7 10v12"/><path d="M15 5.88 14 10h5.83a2 2 0 0 1 1.92 2.56l-2.33 8A2 2 0 0 1 17.5 22H7V10l4-9a1 1 0 0 1 1 1v3a3 3 0 0 1-.5 1.66Z"/></svg>
    </button>
    <button class="m-icon-btn" aria-label="Thumbs down">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 14V2"/><path d="M9 18.12 10 14H4.17a2 2 0 0 1-1.92-2.56l2.33-8A2 2 0 0 1 6.5 2H17v12l-4 9a1 1 0 0 1-1-1v-3a3 3 0 0 1 .5-1.66Z"/></svg>
    </button>
    <span style="display:inline-flex;align-items:center;gap:6px;color:var(--c-primary);font-size:12px;font-weight:500;">
      <span style="width:18px;height:18px;border:2px solid currentColor;border-right-color:transparent;border-radius:50%;display:inline-block;"></span>
      <span style="text-decoration:underline;cursor:pointer;">Tell us why!</span>
    </span>
  </div>
  <p class="small mt-3" style="color:var(--c-muted-fg);">After a thumb tap, a 5-second countdown appears; the user can click "Tell us why!" to open a reason dialog, or let it submit silently.</p>`;

const feedback = demoBlock("feedback", "Feedback buttons",
  feedbackDemo,
  "lib/src/modules/room/ui/feedback_buttons.dart (excerpt)",
  `enum _FeedbackPhase { idle, countdown, modal, submitted }

void _startCountdown(FeedbackType direction) {
  _countdownTimer?.cancel();
  setState(() {
    _phase = _FeedbackPhase.countdown;
    _direction = direction;
  });
  _controller.reverse(from: 1);
  _countdownTimer = Timer(
    Duration(seconds: widget.countdownSeconds),
    () {
      if (mounted && _phase == _FeedbackPhase.countdown) {
        _submit(null);
      }
    },
  );
}`
);

const statusDemo = `
  <div class="demo-col" style="gap:10px;">
    <div style="display:flex;align-items:center;gap:10px;padding:10px 12px;border:1px solid var(--c-border);border-radius:12px;">
      <span style="width:8px;height:8px;border-radius:50%;background:#3b82f6;"></span><span>Info &mdash; 4 documents matched your filter</span>
    </div>
    <div style="display:flex;align-items:center;gap:10px;padding:10px 12px;border:1px solid var(--c-border);border-radius:12px;">
      <span style="width:8px;height:8px;border-radius:50%;background:#22c55e;"></span><span>Success &mdash; Server <code>prod-1</code> connected</span>
    </div>
    <div style="display:flex;align-items:center;gap:10px;padding:10px 12px;border:1px solid var(--c-border);border-radius:12px;">
      <span style="width:8px;height:8px;border-radius:50%;background:#f97316;"></span><span>Warning &mdash; Token expires in 3 minutes</span>
    </div>
    <div style="display:flex;align-items:center;gap:10px;padding:10px 12px;border-radius:12px;background:var(--c-error-container);color:var(--c-on-error-container);">
      <span style="width:8px;height:8px;border-radius:50%;background:currentColor;"></span><span>Error &mdash; Connection to <code>auth.soliplex.ai</code> timed out</span>
    </div>
  </div>`;

const statusSection = demoBlock("status", "Status &amp; Symbolic colors",
  statusDemo,
  "lib/src/design/color/color_scheme_extensions.dart",
  `extension SymbolicColors on ColorScheme {
  Color get info    => brightness == Brightness.light ? Colors.blue   : Colors.blue.shade300;
  Color get warning => brightness == Brightness.light ? Colors.orange : Colors.orange.shade300;
  Color get danger  => brightness == Brightness.light ? Colors.red    : Colors.red.shade300;
  Color get success => brightness == Brightness.light ? Colors.green  : Colors.green.shade300;
}`
);

const architecture = `
<section id="architecture">
  <h2>Architecture</h2>
  <p class="lede">
    The frontend is a modular shell. <code>runSoliplexShell(ShellConfig)</code>
    boots the app from a single config. Each feature module is a plain function
    returning a <code>ModuleContribution</code> (routes + Riverpod overrides +
    optional redirect). Flavors compose modules.
  </p>

  <h3>Theming flow</h3>
  <ol>
    <li><code>SoliplexColors</code> record declared in <code>tokens/colors.dart</code> &mdash; two consts: <code>lightSoliplexColors</code>, <code>darkSoliplexColors</code>.</li>
    <li><code>soliplexLightTheme(colors)</code> maps the record into a full Material 3 <code>ThemeData</code> &mdash; app bar, buttons, inputs, list tiles, chips, cards, expansion tiles, dropdowns, popup menus.</li>
    <li>A <code>SoliplexTheme</code> <code>ThemeExtension</code> carries the raw tokens + <code>SoliplexRadii</code> + <code>SoliplexBadgeThemeData</code> so code paths that need the record (not just the scheme) can read <code>Theme.of(context).extension&lt;SoliplexTheme&gt;()</code>.</li>
    <li>The <code>standard()</code> flavor adds a <code>MarkdownThemeExtension</code> on top for the markdown renderer inside chat messages.</li>
  </ol>

  ${codeBlock("dart", "lib/src/flavors/standard.dart (excerpt)", `ThemeData _defaultTheme() {
  final base = soliplexLightTheme();
  final colorScheme = base.colorScheme;
  final textTheme = base.textTheme;
  final colors = base.extension<SoliplexTheme>()!.colors;

  return base.copyWith(
    extensions: [
      ...base.extensions.values,
      MarkdownThemeExtension(
        h1: textTheme.titleLarge,
        h2: textTheme.titleMedium,
        h3: textTheme.titleSmall,
        body: textTheme.bodyMedium,
        code: textTheme.bodyMedium?.copyWith(
          backgroundColor: colorScheme.surfaceContainerHighest,
        ),
        link: TextStyle(
          color: colors.link,
          decoration: TextDecoration.underline,
          decorationColor: colors.link,
        ),
        codeBlockDecoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ],
  );
}`)}
</section>`;

const usage = `
<section id="usage">
  <h2>Using the theme</h2>
  <p>Read tokens the Material way first. Drop to <code>SoliplexTheme.of</code> only when the Material scheme doesn't expose what you need.</p>

  ${codeBlock("dart", "preferred · read through ColorScheme + TextTheme", `@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Container(
    padding: const EdgeInsets.all(SoliplexSpacing.s3),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text('Thread title', style: theme.textTheme.titleSmall),
  );
}`)}

  ${codeBlock("dart", "when you need the raw record", `final soliplex = Theme.of(context).extension<SoliplexTheme>()!;
final linkColor  = soliplex.colors.link;
final mdRadius   = soliplex.radii.md;
final badgeStyle = soliplex.badgeTheme.textStyle;`)}

  ${codeBlock("dart", "monospace helper (BuildContext extension)", `import 'package:soliplex_frontend/src/design/design.dart';

// …inside a build method
Text('agent_id: 42', style: context.monospace);`)}
</section>`;

const adoption = `
<section id="adoption">
  <h2>Adoption checklist</h2>
  <p>When writing a new screen or widget, run through the list. If any box is unchecked, the code shouldn't land.</p>
  <ul>
    <li>☐ Colors come from <code>Theme.of(context).colorScheme</code>, not hex literals.</li>
    <li>☐ Padding values come from <code>SoliplexSpacing</code> (<code>s1..s6</code>).</li>
    <li>☐ Corner radii come from <code>soliplexRadii</code> via <code>SoliplexTheme.of(context).radii</code>.</li>
    <li>☐ Text styles come from <code>Theme.of(context).textTheme</code>.</li>
    <li>☐ Monospace uses <code>context.monospace</code>, not a hardcoded font family.</li>
    <li>☐ Semantic colors for status go through the <code>SymbolicColors</code> extension.</li>
    <li>☐ The screen behaves at all three <code>SoliplexBreakpoints</code>.</li>
    <li>☐ Both <code>lightSoliplexColors</code> and <code>darkSoliplexColors</code> look correct.</li>
    <li>☐ Destructive actions use <code>colorScheme.error</code>; never red hex.</li>
  </ul>
  <div class="callout">
    Running a 4-point checklist before PR has caught more drift than any
    lint rule. When a token is missing from the system, <em>add</em> it to
    <code>SoliplexColors</code> or <code>SoliplexSpacing</code> &mdash; don't
    inline a value.
  </div>
</section>`;

window.__SECTIONS_2 = {
  typography, spacing, radii, breakpoints,
  componentsIntro, buttons, inputs, cards, chips, chat, feedback, statusSection,
  architecture, usage, adoption
};
