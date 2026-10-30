import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' show ThreadLabel;
import 'package:soliplex_design/soliplex_design.dart';

/// The colour to paint [label] with.
///
/// Falls back to a tint hashed from the name when the stored swatch does
/// not parse — a label with an unreadable colour is still a usable label,
/// and a blank chip would look like a rendering fault.
Color labelColor(ThreadLabel label, Brightness brightness) =>
    colorFromHex(label.color) ?? hashedHueColor(label.name, brightness);

/// A chip for one label, in the label's own colour.
class LabelChip extends StatelessWidget {
  const LabelChip({super.key, required this.label, this.onDeleted});

  final ThreadLabel label;

  /// Shows a trailing close button when non-null.
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return SoliplexChip.colored(
      label: Text(label.name),
      color: labelColor(label, Theme.of(context).brightness),
      onDeleted: onDeleted,
    );
  }
}
