import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';

void main() {
  test('roomAboveChatInputBuildersProvider defaults to const empty', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final builders = container.read(roomAboveChatInputBuildersProvider);
    expect(builders, isEmpty);
  });

  test('roomChatInputToolbarBuildersProvider defaults to const empty', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final builders = container.read(roomChatInputToolbarBuildersProvider);
    expect(builders, isEmpty);
  });

  test('slot providers are overridable', () {
    final container = ProviderContainer(
      overrides: [
        roomAboveChatInputBuildersProvider.overrideWithValue([
          (_) => const SizedBox.shrink(),
        ]),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(roomAboveChatInputBuildersProvider), hasLength(1));
  });
}
