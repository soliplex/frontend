import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/room_grid_layout.dart';

void main() {
  group('roomGridColumns', () {
    test('one column below the mobile breakpoint', () {
      expect(roomGridColumns(SoliplexBreakpoints.mobile - 1), 1);
    });

    test('two columns from the mobile breakpoint up to desktop', () {
      expect(roomGridColumns(SoliplexBreakpoints.mobile), 2);
      expect(roomGridColumns(SoliplexBreakpoints.desktop - 1), 2);
    });

    test('three columns at the desktop breakpoint and wider', () {
      expect(roomGridColumns(SoliplexBreakpoints.desktop), 3);
      expect(roomGridColumns(SoliplexBreakpoints.desktop + 200), 3);
    });
  });
}
