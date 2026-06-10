import 'package:soliplex_design/soliplex_design.dart';

/// Column count for the lobby room grid at a given [width].
///
/// Three columns at [SoliplexBreakpoints.desktop] and wider, two at
/// [SoliplexBreakpoints.mobile] and wider, one below that.
int roomGridColumns(double width) {
  return width >= SoliplexBreakpoints.desktop
      ? 3
      : width >= SoliplexBreakpoints.mobile
          ? 2
          : 1;
}
