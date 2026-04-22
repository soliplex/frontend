import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/thread_view_state.dart';
import 'package:soliplex_frontend/src/modules/room/ui/extension_state_panel.dart';

class _MockThreadViewState extends Mock implements ThreadViewState {}

Widget _frame(ThreadViewState view) {
  return MaterialApp(
    home: Scaffold(body: ExtensionStatePanel(threadView: view)),
  );
}

void main() {
  late _MockThreadViewState view;
  late Signal<AgentSessionState?> sessionStateSignal;

  setUp(() {
    view = _MockThreadViewState();
    sessionStateSignal = Signal<AgentSessionState?>(null);
    when(() => view.sessionState).thenReturn(sessionStateSignal.readonly());
    when(() => view.statefulObservations)
        .thenReturn(const <(String, ReadonlySignal<Object?>)>[]);
  });

  tearDown(() {
    sessionStateSignal.dispose();
    reset(view);
  });

  group('ExtensionStatePanel', () {
    testWidgets('renders nothing when observations is empty', (tester) async {
      await tester.pumpWidget(_frame(view));

      expect(find.byType(ExtensionStatePanel), findsOneWidget);
      expect(find.text('EXTENSIONS'), findsNothing);
    });

    testWidgets('renders header when there are observations', (tester) async {
      final sig = Signal<Object?>({'step': 1});
      when(() => view.statefulObservations)
          .thenReturn([(('my_ext', sig.readonly()))]);

      await tester.pumpWidget(_frame(view));

      expect(find.text('EXTENSIONS'), findsOneWidget);
      sig.dispose();
    });

    testWidgets('badge shows correct extension count', (tester) async {
      final s1 = Signal<Object?>(1);
      final s2 = Signal<Object?>(2);
      when(() => view.statefulObservations).thenReturn([
        ('ext_a', s1.readonly()),
        ('ext_b', s2.readonly()),
      ]);

      await tester.pumpWidget(_frame(view));

      expect(find.text('2'), findsOneWidget);
      s1.dispose();
      s2.dispose();
    });

    testWidgets('panel is collapsed by default (rows not visible)',
        (tester) async {
      final sig = Signal<Object?>({'x': 1});
      when(() => view.statefulObservations)
          .thenReturn([('my_ext', sig.readonly())]);

      await tester.pumpWidget(_frame(view));

      expect(find.text('my_ext'), findsNothing);
      sig.dispose();
    });

    testWidgets('tapping header expands the panel', (tester) async {
      final sig = Signal<Object?>({'x': 1});
      when(() => view.statefulObservations)
          .thenReturn([('my_ext', sig.readonly())]);

      await tester.pumpWidget(_frame(view));

      await tester.tap(find.text('EXTENSIONS'));
      await tester.pump();

      expect(find.text('my_ext'), findsOneWidget);
      sig.dispose();
    });

    testWidgets('tapping header again collapses the panel', (tester) async {
      final sig = Signal<Object?>({'x': 1});
      when(() => view.statefulObservations)
          .thenReturn([('my_ext', sig.readonly())]);

      await tester.pumpWidget(_frame(view));

      await tester.tap(find.text('EXTENSIONS'));
      await tester.pump();
      expect(find.text('my_ext'), findsOneWidget);

      await tester.tap(find.text('EXTENSIONS'));
      await tester.pump();
      expect(find.text('my_ext'), findsNothing);
      sig.dispose();
    });

    testWidgets('expanded panel renders namespace label for each extension',
        (tester) async {
      final s1 = Signal<Object?>(1);
      final s2 = Signal<Object?>('hello');
      when(() => view.statefulObservations).thenReturn([
        ('counter', s1.readonly()),
        ('greeter', s2.readonly()),
      ]);

      await tester.pumpWidget(_frame(view));
      await tester.tap(find.text('EXTENSIONS'));
      await tester.pump();

      expect(find.text('counter'), findsOneWidget);
      expect(find.text('greeter'), findsOneWidget);
      s1.dispose();
      s2.dispose();
    });

    testWidgets('expanded panel JSON-encodes signal value', (tester) async {
      final sig = Signal<Object?>(42);
      when(() => view.statefulObservations)
          .thenReturn([('my_ext', sig.readonly())]);

      await tester.pumpWidget(_frame(view));
      await tester.tap(find.text('EXTENSIONS'));
      await tester.pump();

      expect(find.text('42'), findsOneWidget);
      sig.dispose();
    });

    testWidgets('panel refreshes observations when sessionState changes',
        (tester) async {
      when(() => view.statefulObservations)
          .thenReturn(const <(String, ReadonlySignal<Object?>)>[]);

      await tester.pumpWidget(_frame(view));
      expect(find.text('EXTENSIONS'), findsNothing);

      final sig = Signal<Object?>(1);
      when(() => view.statefulObservations)
          .thenReturn([('new_ext', sig.readonly())]);

      sessionStateSignal.value = AgentSessionState.running;
      await tester.pump();

      expect(find.text('EXTENSIONS'), findsOneWidget);
      sig.dispose();
    });

    testWidgets('rebinds when threadView changes', (tester) async {
      final view2 = _MockThreadViewState();
      final sessionStateSignal2 = Signal<AgentSessionState?>(null);
      final sig = Signal<Object?>(99);
      when(() => view2.sessionState).thenReturn(sessionStateSignal2.readonly());
      when(() => view2.statefulObservations)
          .thenReturn([('ext_v2', sig.readonly())]);

      await tester.pumpWidget(_frame(view));
      expect(find.text('EXTENSIONS'), findsNothing);

      await tester.pumpWidget(_frame(view2));
      await tester.pump();
      expect(find.text('EXTENSIONS'), findsOneWidget);

      sig.dispose();
      sessionStateSignal2.dispose();
    });
  });
}
