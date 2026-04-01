# Citations UI — Implementation Plan

Builds on `fix/live-citations` branch where `RunOrchestrator` already
populates `conversation.messageStates` with citations and `runId` on
all terminal state transitions.

Reference: `feat/citations/docs/plans/citations-port/decisions.md`

## Design decisions

### Rejected alternatives

- **MessageContext object** bundling per-message data (runId,
  sourceReferences, executionTracker, streamingActivity) into a single
  parameter. Rejected because the fields are semantically unrelated —
  it's a bag, not a concept. At 4 data fields it's premature. Revisit
  if per-message data grows significantly.
- **Citation as sibling list item** in MessageTimeline rather than child
  of TextMessageTile. Rejected because it breaks the requirement to
  render citations below the action buttons (copy, feedback).

### Data model limitation

`MessageState` is keyed by **user message ID**. All citations from a
run are stored as a single flat `List<SourceReference>`. There is no
per-assistant-message association — if a run produces multiple
assistant text messages, there's no way to know which citations belong
to which.

This is a backend + client limitation, not a frontend one. Fixing it
requires:

1. Backend emitting citations tied to specific assistant message IDs
   (e.g., via custom AG-UI events)
2. Client extracting citations per-message rather than per-run

For this port, we accept the limitation and show all run citations on
the **last assistant TextMessage** per turn.

## Prerequisites (already done)

- `RunOrchestrator` extracts citations on completion, error, cancel
- `ThreadViewState._messagesLoaded` merges `messageStates` via
  `{...existing, ...conversation.messageStates}` — conversation
  values win, which is correct because `RunOrchestrator._extractCitations`
  populates citations before emitting terminal states
- `SourceReference` model with `displayTitle`, `isPdf`,
  `formattedPageNumbers` extensions
- `SoliplexApi.getChunkVisualization(roomId, chunkId)` exists
- `ChunkVisualization` model exists

## Data flow: callback pattern

`RoomScreen` owns the `SoliplexApi` via
`widget.serverEntry.connection.api`. Rather than threading the API
through presentational widgets, we use a callback — matching the
existing pattern for `onInspect` and `onFeedbackSubmit`.

```text
RoomScreen (owns api, provides onShowChunkVisualization callback)
  └─ MessageTimeline (forwards callback)
       └─ MessageTile (forwards callback)
            └─ TextMessageTile (forwards callback)
                 └─ CitationsSection (calls callback on PDF tap)
```

`ChunkVisualizationPage.show()` is called in `RoomScreen`'s callback
implementation, keeping API access at the layer that owns it.

```dart
onShowChunkVisualization: (ref) => ChunkVisualizationPage.show(
  context: context,
  api: widget.serverEntry.connection.api,
  roomId: roomId,
  chunkId: ref.chunkId,
  documentTitle: ref.displayTitle,
  pageNumbers: ref.pageNumbers,
),
```

## Step 1: source_references_resolver.dart (TDD)

New file: `lib/src/modules/room/source_references_resolver.dart`

Function: `buildSourceReferencesMap(messages, messageStates)`
returns `Map<String, List<SourceReference>>` mapping assistant message
ID to citations.

Algorithm (forward iteration, matching `buildRunIdMap` pattern):

1. Iterate messages from start to end.
2. Track `currentUserMessageId` (initially null) and
   `lastAssistantTextMessageId` (initially null).
3. When hitting any message with `user == ChatUser.user` (turn
   boundary, any message type — not just TextMessage):
   - Call `assignPendingCitations()` to finalize the previous turn.
   - Set `currentUserMessageId = msg.id`, reset
     `lastAssistantTextMessageId = null`.
4. When hitting a `TextMessage` with `user != ChatUser.user`:
   set `lastAssistantTextMessageId = msg.id` (overwrites previous,
   so the last one wins).
5. Skip non-TextMessage assistant messages (ToolCallMessage,
   ErrorMessage, etc.) — they don't change tracking state.
6. After loop: call `assignPendingCitations()` for the final turn.

Helper `assignPendingCitations()`: if both `currentUserMessageId` and
`lastAssistantTextMessageId` are non-null, look up
`messageStates[currentUserMessageId]?.sourceReferences` — if
non-empty, assign to `lastAssistantTextMessageId` in the result map.

This assigns citations to the **last assistant TextMessage** per turn,
matching the decisions doc. The turn boundary uses
`message.user == ChatUser.user` (not `message is TextMessage`) to
mirror `buildRunIdMap` and handle future non-text user message types.

Edge cases (from decisions doc):

| Scenario                                           | Result                              |
| -------------------------------------------------- | ----------------------------------- |
| User -> AssistantText                              | Citations on that assistant message |
| User -> ToolCall -> AssistantText                  | Citations on the text message       |
| User -> AssistantText -> ToolCall -> AssistantText | Citations on 2nd text (accepted)    |
| User (failed) -> User2 -> AssistantText            | Citations from User2 only           |
| No user messages, only assistant                   | No citations                        |
| User -> only ToolCalls, no TextMessage             | No citations displayed              |

Test file: `test/modules/room/source_references_resolver_test.dart`

## Step 2: Wire through widget tree

### message_timeline.dart

- Call `buildSourceReferencesMap` alongside existing `buildRunIdMap`.
- Add `void Function(SourceReference)? onShowChunkVisualization`
  parameter.
- Pass `sourceReferences[message.id]` and
  `onShowChunkVisualization` to `MessageTile`.

### message_tile.dart

- Add `List<SourceReference>? sourceReferences` and
  `void Function(SourceReference)? onShowChunkVisualization`
  parameters.
- Forward to `TextMessageTile` only (other tile types ignore them).

### text_message_tile.dart

- Add `List<SourceReference>? sourceReferences` and
  `void Function(SourceReference)? onShowChunkVisualization`
  parameters.
- After the action buttons `Row` (last child of main `Column`),
  render `CitationsSection` when `sourceReferences` is non-empty.
  No `!isUser` guard needed — `buildSourceReferencesMap` only maps
  assistant message IDs, so user messages will have null references.

### room_screen.dart

- Implement `onShowChunkVisualization` callback that calls
  `ChunkVisualizationPage.show()` with the API from
  `widget.serverEntry.connection.api`.
- Pass callback to `MessageTimeline`.

## Step 3: citations_section.dart

New file: `lib/src/modules/room/ui/citations_section.dart`

Add `url_launcher` dependency to `pubspec.yaml` (needed for link taps
in citation markdown content).

Adapted from old repo, StatefulWidget instead of Riverpod.

### CitationsSection

Parameters: `sourceReferences`, `onShowChunkVisualization`.

`CitationsSection` is a `StatefulWidget`. Local `State` holds:

- `bool _sectionExpanded` for the section header
- `Set<int> _expandedIndices` for individual citations (by list
  position)

No `messageId` needed — each instance owns its own state scope.

Expand state is lost when the widget is disposed (e.g., scrolling far
off-screen past `SliverList` cache extent). Acceptable for now. If
preserving state across deep scrolling becomes a requirement, extract
a `CitationExpandState` class owned by `MessageTimeline` and passed
down.

Structure:

- **Header**: quote icon + "N source(s)" + expand/collapse chevron.
  Taps toggle `_sectionExpanded`.
- **Expanded body**: list of `_SourceReferenceRow` widgets.

### _SourceReferenceRow

- **Always visible**: numbered badge + `displayTitle` +
  `formattedPageNumbers`.
  Badge number: use `sourceReference.index` (1-based, set by
  backend). The backend assigns session-global indices in `ask()` —
  if turn 1 has citations 1-3, turn 2 starts at 4. This matches
  in-text citation references like "[4]". Fall back to
  `listPosition + 1` only if `index` is null (defensive; shouldn't
  happen for `qa_history` citations).
- **When expanded** (taps toggle list position in
  `_expandedIndices`):
  - Headings breadcrumb (`headings.join(' > ')`)
  - Content preview: markdown rendered via `FlutterMarkdownPlusRenderer`,
    max height 250px, scrollable
  - File path (documentUri)
  - PDF view button (visible when `isPdf`) calls
    `onShowChunkVisualization(sourceReference)`

### Styling

Use existing Material 3 theme values from the codebase:

- `colorScheme.surfaceContainerHighest` for content preview background
- `colorScheme.primaryContainer` for numbered badge background
- `colorScheme.onSurfaceVariant` for muted text
- 12px border radius (matches existing message bubbles)
- No custom design tokens

Test file: `test/modules/room/ui/citations_section_test.dart`

## Step 4: chunk_visualization_page.dart

New file: `lib/src/modules/room/ui/chunk_visualization_page.dart`

Dialog (not route) showing PDF chunk page images. Called directly from
`RoomScreen`'s `onShowChunkVisualization` callback — never threaded
through intermediate widgets.

### ChunkVisualizationPage

Parameters: `api`, `roomId`, `chunkId`, `documentTitle`,
`pageNumbers`.

Static `show()` method using `showDialog`.

### Behavior

1. On init: call `api.getChunkVisualization(roomId, chunkId)`
2. Loading: centered `CircularProgressIndicator`
3. Error: error message with retry button
4. Success: `PageView` of base64-decoded images
5. Per-image rotation (90 degree increments) via state tracking
6. Pinch-to-zoom via `InteractiveViewer`
7. Page indicator dots at bottom
8. Title bar showing `documentTitle` and page number

Port close to 1:1 from old repo — rotation and zoom are existing
tested functionality.

Test file: `test/modules/room/ui/chunk_visualization_page_test.dart`

## Step 5: Widget tests

`source_references_resolver_test.dart` is written during Step 1 via
TDD. This step covers widget tests for Steps 3 and 4, which need the
widgets to exist first.

| Test file                              | Covers                                      |
| -------------------------------------- | ------------------------------------------- |
| `citations_section_test.dart`          | Header count, expand/collapse, content, PDF |
| `chunk_visualization_page_test.dart`   | Loading, images, error, rotation            |

## Step 6: Cleanup

- Run `dart format .`
- Run `flutter analyze` (zero warnings)
- Run `flutter test` (all pass)
- Lint any new markdown files

## File inventory

| File                                                      | Action |
| --------------------------------------------------------- | ------ |
| `lib/src/modules/room/source_references_resolver.dart`    | New    |
| `lib/src/modules/room/ui/citations_section.dart`          | New    |
| `lib/src/modules/room/ui/chunk_visualization_page.dart`   | New    |
| `lib/src/modules/room/ui/message_timeline.dart`           | Modify |
| `lib/src/modules/room/ui/message_tile.dart`               | Modify |
| `lib/src/modules/room/ui/text_message_tile.dart`          | Modify |
| `lib/src/modules/room/ui/room_screen.dart`                | Modify |
| `test/modules/room/source_references_resolver_test.dart`  | New    |
| `test/modules/room/ui/citations_section_test.dart`        | New    |
| `test/modules/room/ui/chunk_visualization_page_test.dart` | New    |

## Execution order

Step 1 first (TDD — resolver tests written here).
Step 2 depends on 1 (parameter signatures).
Steps 3 and 4 are independent (parallel), depend on 2 for
parameter signatures.
Step 5 widget tests for 3 and 4 (after widgets exist).
Step 6 final cleanup.

## Not in scope

- Design tokens (`SoliplexSpacing`, custom radii) — use hardcoded
  Material 3 values
- Changes to `MessageState` keying (accept per-user-message
  limitation)
- Incremental citation extraction during streaming (future
  enhancement per issue #44)
