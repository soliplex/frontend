import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/ui/tool_call_tile.dart';
import 'package:soliplex_frontend/src/shared/content/code_view.dart';
import 'package:soliplex_frontend/src/shared/content/json_viewer.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

ToolCallMessage makeMessage(List<ToolCallInfo> toolCalls) => ToolCallMessage(
      id: 'msg-1',
      createdAt: DateTime(2026),
      toolCalls: toolCalls,
    );

void main() {
  testWidgets('renders tool name and status for single tool call',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        ToolCallTile(
          message: makeMessage([
            const ToolCallInfo(
              id: 'tc-1',
              name: 'search_web',
              status: ToolCallStatus.completed,
            ),
          ]),
        ),
      ),
    );

    expect(find.text('search_web'), findsOneWidget);
    expect(find.text('completed'), findsOneWidget);
  });

  testWidgets('renders multiple tool calls', (tester) async {
    await tester.pumpWidget(
      wrap(
        ToolCallTile(
          message: makeMessage([
            const ToolCallInfo(
              id: 'tc-1',
              name: 'search_web',
              status: ToolCallStatus.completed,
            ),
            const ToolCallInfo(
              id: 'tc-2',
              name: 'read_file',
              status: ToolCallStatus.pending,
            ),
          ]),
        ),
      ),
    );

    expect(find.text('search_web'), findsOneWidget);
    expect(find.text('read_file'), findsOneWidget);
    expect(find.text('completed'), findsOneWidget);
    expect(find.text('pending'), findsOneWidget);
  });

  testWidgets('expansion shows arguments in a JsonViewer', (tester) async {
    await tester.pumpWidget(
      wrap(
        ToolCallTile(
          message: makeMessage([
            const ToolCallInfo(
              id: 'tc-1',
              name: 'search_web',
              arguments: '{"query": "flutter test"}',
              status: ToolCallStatus.completed,
            ),
          ]),
        ),
      ),
    );

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    expect(find.byType(JsonViewer), findsOneWidget);
    expect(find.text('Arguments'), findsOneWidget);
    expect(find.text('Tree'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(find.byTooltip('Copy Arguments'), findsOneWidget);
    expect(
      tester.widget<CodeView>(find.byType(CodeView)).code,
      '{\n  "query": "flutter test"\n}',
    );
  });

  testWidgets('arguments inside a SelectionArea add no SelectableText',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: ToolCallTile(
              message: makeMessage([
                const ToolCallInfo(
                  id: 'tc-1',
                  name: 'search_web',
                  arguments: '{"query": "flutter test"}',
                  status: ToolCallStatus.completed,
                ),
              ]),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    expect(find.byType(JsonViewer), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('expansion shows result when hasResult', (tester) async {
    const result = '{"status": "ok"}';
    await tester.pumpWidget(
      wrap(
        ToolCallTile(
          message: makeMessage([
            const ToolCallInfo(
              id: 'tc-1',
              name: 'search_web',
              result: result,
              status: ToolCallStatus.completed,
            ),
          ]),
        ),
      ),
    );

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsOneWidget);
    expect(find.text(result), findsOneWidget);
  });

  testWidgets('hides arguments section when empty', (tester) async {
    await tester.pumpWidget(
      wrap(
        ToolCallTile(
          message: makeMessage([
            const ToolCallInfo(
              id: 'tc-1',
              name: 'no_args_tool',
              status: ToolCallStatus.completed,
            ),
          ]),
        ),
      ),
    );

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    expect(find.text('Arguments'), findsNothing);
  });

  testWidgets('hides result section when empty', (tester) async {
    await tester.pumpWidget(
      wrap(
        ToolCallTile(
          message: makeMessage([
            const ToolCallInfo(
              id: 'tc-1',
              name: 'pending_tool',
              status: ToolCallStatus.pending,
            ),
          ]),
        ),
      ),
    );

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsNothing);
  });
}
