import 'chat/chat_mockup.dart';
import 'datasets/classification_levels.dart';
import 'datasets/datasets_mockup.dart';
import 'example_mockup.dart';
import 'mockup.dart';

/// Every mockup the harness lists, in the order shown.
///
/// Add a screen by dropping its widget next to this file and adding one
/// entry here.
final mockups = <Mockup>[
  Mockup(
    name: 'Chat',
    description: 'The room screen on a static backend; sending gets a '
        'scripted reply',
    build: (_) => const ChatMockup(),
  ),
  Mockup(
    name: 'Datasets',
    description: 'Rooms as presets, a catalog of datasets to pick from, and '
        'creating, uploading to and sharing your own',
    classifications: mockupClassifications,
    build: (_) => const DatasetsMockup(),
  ),
  Mockup(
    name: 'Example',
    description: 'Logo, branded components, status colors, breakpoint switch',
    build: (_) => const ExampleMockup(),
  ),
];
