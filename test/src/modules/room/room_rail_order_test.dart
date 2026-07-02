import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/room/room_unread.dart';

// Minimal Room builder — only id/name matter to the ordering.
Room _room(String id, String name) => Room(id: id, name: name);

DateTime _t(int day) => DateTime.utc(2026, 1, day);

void main() {
  group('orderRoomsForRail', () {
    test('pins the selected room first regardless of its activity', () {
      final rooms = [
        _room('a', 'Alpha'),
        _room('b', 'Bravo'),
        _room('c', 'Cee')
      ];
      final order = orderRoomsForRail(
        rooms,
        {'a': _t(1), 'b': _t(5), 'c': null},
        {'b'}, // b is unread
        selectedRoomId: 'a',
      );
      expect(order.rooms.first.id, 'a');
    });

    test('orders unread rooms newest activity first, below the selected room',
        () {
      final rooms = [
        _room('a', 'Sel'),
        _room('old', 'Old'),
        _room('new', 'New')
      ];
      final order = orderRoomsForRail(
        rooms,
        {'a': _t(1), 'old': _t(2), 'new': _t(9)},
        {'old', 'new'},
        selectedRoomId: 'a',
      );
      expect(order.rooms.map((r) => r.id).toList(), ['a', 'new', 'old']);
    });

    test('a room that just got activity lands right below the selected room',
        () {
      // The "new activity slots below current room" behaviour falls out of
      // unread-newest-first + selected-pinned-top.
      final rooms = [_room('sel', 'Sel'), _room('x', 'X'), _room('y', 'Y')];
      final order = orderRoomsForRail(
        rooms,
        {'sel': _t(1), 'x': _t(3), 'y': _t(20)}, // y just pinged
        {'x', 'y'},
        selectedRoomId: 'sel',
      );
      expect(order.rooms[1].id, 'y');
    });

    test(
        'read rooms follow unread, newest first; no-activity rooms last '
        'alphabetically', () {
      final rooms = [
        _room('z', 'Zeta'),
        _room('m', 'Mid'),
        _room('u', 'Unread'),
        _room('a', 'Aardvark'),
      ];
      final order = orderRoomsForRail(
        rooms,
        {'z': _t(4), 'm': _t(8), 'u': _t(9), 'a': null},
        {'u'},
        selectedRoomId: null,
      );
      // unread(u) | read-by-activity: m(8) then z(4) | no-activity: a
      expect(order.rooms.map((r) => r.id).toList(), ['u', 'm', 'z', 'a']);
    });

    test(
        'divider index is the first read-section room when both sections '
        'are non-empty', () {
      final rooms = [_room('s', 'Sel'), _room('u', 'U'), _room('r', 'R')];
      final order = orderRoomsForRail(
        rooms,
        {'s': _t(1), 'u': _t(5), 'r': _t(2)},
        {'u'},
        selectedRoomId: 's',
      );
      // ['s'(0), 'u'(1), 'r'(2)] -> read starts at index 2
      expect(order.dividerIndex, 2);
    });

    test('no divider when there are no unread rooms', () {
      final rooms = [_room('s', 'Sel'), _room('r', 'R')];
      final order = orderRoomsForRail(
        rooms,
        {'s': _t(1), 'r': _t(2)},
        const {},
        selectedRoomId: 's',
      );
      expect(order.dividerIndex, isNull);
    });

    test('no divider when there are no read rooms', () {
      final rooms = [_room('s', 'Sel'), _room('u', 'U')];
      final order = orderRoomsForRail(
        rooms,
        {'s': _t(1), 'u': _t(9)},
        {'u'},
        selectedRoomId: 's',
      );
      expect(order.dividerIndex, isNull);
    });

    test('no-activity rooms tie-break alphabetically, case-insensitively', () {
      final rooms = [_room('b', 'bravo'), _room('a', 'Alpha')];
      final order = orderRoomsForRail(
        rooms,
        {'a': null, 'b': null},
        const {},
        selectedRoomId: null,
      );
      expect(order.rooms.map((r) => r.id).toList(), ['a', 'b']);
    });
  });
}
