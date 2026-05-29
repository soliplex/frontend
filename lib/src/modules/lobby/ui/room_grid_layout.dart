import 'package:soliplex_design/soliplex_design.dart';

/// Column count and cell width for the lobby room grid at a given [width],
/// laid out with [spacing] between cells.
///
/// Three columns at [SoliplexBreakpoints.desktop] and wider, two at
/// [SoliplexBreakpoints.mobile] and wider, one below that. The cell width
/// removes the inter-cell gaps (`columns - 1` of them) before dividing the
/// remaining width evenly.
({int columns, double cellWidth}) roomGridLayout(
  double width, {
  double spacing = SoliplexSpacing.s3,
}) {
  final columns = width >= SoliplexBreakpoints.desktop
      ? 3
      : width >= SoliplexBreakpoints.mobile
          ? 2
          : 1;
  final cellWidth = (width - spacing * (columns - 1)) / columns;
  return (columns: columns, cellWidth: cellWidth);
}
