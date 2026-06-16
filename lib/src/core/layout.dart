/// Shared layout constants for content sizing across feature modules.
library;

// REORG NEEDED: content-width caps are scattered across the app — this
// form-column width, the chat timeline cap (840, `_maxContentWidth` in
// room_screen.dart), and the preview dialog caps (800, chunk visualization /
// workdir preview). They should be consolidated into one layout-token home so
// the values are discoverable and managed together; a candidate is the
// soliplex_design package alongside SoliplexBreakpoints.

/// Maximum width of a centered form/content column on wide viewports, so forms
/// and cards don't stretch edge-to-edge on desktop/web.
///
/// Shared by the onboarding/connect flow (HomeShell) and the quiz forms so the
/// form surfaces stay visually aligned. This is deliberately independent of
/// SoliplexBreakpoints — it's a content width, not a layout breakpoint, and the
/// two should not drift together.
const double formColumnMaxWidth = 600;
