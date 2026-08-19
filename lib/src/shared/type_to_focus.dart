import 'package:flutter/services.dart';

final _modifierKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
};

/// Whether a key press should pull focus into a text field ("type to focus").
/// Only real typing does - never a bare modifier, and never while a shortcut
/// modifier is held, so shortcuts like copy and select-all leave the surrounding
/// selection intact instead of clearing it by moving focus.
///
/// Control *combined with* alt is treated as typing, not a shortcut: Windows
/// synthesizes AltGr as Ctrl+Alt to compose special characters (`@`, `\u20ac`,
/// `{`), so those keystrokes must still focus-and-type. Plain Alt/Option is
/// likewise typing. A genuine Ctrl+Alt shortcut therefore focuses the field too,
/// which is harmless: callers move focus and leave the keystroke to run its
/// normal course, so the shortcut still fires.
bool shouldFocusInputOnKey(
  KeyEvent event, {
  required bool isMetaPressed,
  required bool isControlPressed,
  required bool isAltPressed,
}) {
  if (event is! KeyDownEvent) return false;
  if (_modifierKeys.contains(event.logicalKey)) return false;
  final shortcutModifierActive =
      isMetaPressed || (isControlPressed && !isAltPressed);
  return !shortcutModifierActive;
}

/// Whether [character] is text a field should receive, as opposed to a control
/// code that a key happens to report.
///
/// Platforms disagree. The Windows engine filters non-printables out of
/// [KeyEvent.character], but the macOS and Linux engines pass them through, so
/// Enter arrives as a carriage return, Tab as a tab, and Escape as U+001B.
/// Inserting those corrupts a field silently: `String.trim()` strips the first
/// two but not an escape.
bool isTypedText(String? character) {
  if (character == null || character.isEmpty) return false;
  final code = character.codeUnitAt(0);
  return code >= 0x20 && code != 0x7F;
}
