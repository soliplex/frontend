import 'example_mockup.dart';
import 'mockup.dart';

/// Every mockup the harness lists, in the order shown.
///
/// Add a screen by dropping its widget next to this file and adding one
/// entry here.
final mockups = <Mockup>[
  Mockup(
    name: 'Example',
    description: 'Logo, branded components, status colors, breakpoint switch',
    build: (_) => const ExampleMockup(),
  ),
];
