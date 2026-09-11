import 'package:soliplex_client/soliplex_client.dart';

import 'static_backend.dart';

/// The rooms, threads and conversations the chat mockup opens on.
///
/// Fresh maps each call, so hot-restarting the harness resets what a scripted
/// reply or a deleted thread changed.
StaticSoliplexApi sampleApi() {
  // UTC throughout, as the backend sends it; the models assert on it.
  final today = DateTime.now();
  final yesterday = today.subtract(const Duration(days: 1));
  DateTime at(DateTime day, int hour, int minute) =>
      DateTime(day.year, day.month, day.day, hour, minute).toUtc();

  return StaticSoliplexApi(
    rooms: [
      const Room(
        id: 'research',
        name: 'Research assistant',
        description: 'Ask about the papers in the corpus.',
        welcomeMessage:
            'Ask a question about the indexed papers. Answers cite the '
            'passages they draw on.',
        suggestions: [
          'Summarise the latest paper on retrieval',
          'Which papers discuss evaluation?',
          'Compare the two survey papers',
        ],
        acceptsThreadUploads: true,
      ),
      const Room(
        id: 'codebase',
        name: 'Codebase Q&A',
        description: 'Questions about the frontend repository.',
        welcomeMessage: 'Ask about any part of the codebase.',
        suggestions: ['How does the module system work?'],
      ),
      const Room(
        id: 'triage',
        name: 'Support triage',
        description: 'Draft replies to support tickets.',
      ),
    ],
    threads: {
      'research': [
        ThreadInfo(
          id: 'retrieval',
          roomId: 'research',
          name: 'Retrieval paper summary',
          createdAt: at(yesterday, 9, 12),
          lastActivity: at(today, 10, 4),
        ),
        ThreadInfo(
          id: 'evaluation',
          roomId: 'research',
          name: 'Evaluation methods',
          createdAt: at(yesterday, 15, 30),
          lastActivity: at(yesterday, 15, 42),
        ),
        ThreadInfo(
          id: 'untitled',
          roomId: 'research',
          createdAt: at(yesterday, 8, 0),
          lastActivity: at(yesterday, 8, 0),
        ),
      ],
      'codebase': [
        ThreadInfo(
          id: 'modules',
          roomId: 'codebase',
          name: 'Module system',
          createdAt: at(yesterday, 11, 0),
          lastActivity: at(yesterday, 11, 20),
        ),
      ],
      'triage': [],
    },
    histories: {
      'retrieval': ThreadHistory(
        messages: [
          TextMessage(
            id: 'u1',
            user: ChatUser.user,
            createdAt: at(yesterday, 9, 12),
            text: 'Summarise the latest paper on retrieval.',
          ),
          TextMessage(
            id: 'a1',
            user: ChatUser.assistant,
            createdAt: at(yesterday, 9, 13),
            text: '''
The most recent retrieval paper in the corpus is **"Dense Passage Retrieval
Revisited"** (2025). Its main claims:

1. A single dense encoder trained with hard negatives matches hybrid
   sparse–dense systems on in-domain benchmarks.
2. Out of domain, the gap reopens — the authors attribute it to vocabulary
   shift rather than model capacity.
3. Re-ranking the top 20 with a cross-encoder recovers most of that gap at
   roughly 3× the latency.

| Setting | nDCG@10 | Latency |
| ------- | ------- | ------- |
| Sparse  | 0.41    | 12 ms   |
| Dense   | 0.47    | 18 ms   |
| Hybrid  | 0.49    | 31 ms   |
| Dense + re-rank | 0.52 | 55 ms |

The evaluation section is short; the earlier survey in this corpus covers
the same benchmarks in more depth.''',
          ),
          TextMessage(
            id: 'u2',
            user: ChatUser.user,
            createdAt: at(today, 10, 2),
            text: 'What did they use for hard negatives?',
          ),
          TextMessage(
            id: 'a2',
            user: ChatUser.assistant,
            createdAt: at(today, 10, 4),
            text: '''
Two sources, mixed per batch:

- **BM25 negatives** — top-ranked sparse results that are not labelled
  relevant.
- **In-batch negatives** — every other query's positive passage.

They note that BM25 negatives alone over-fit to lexical overlap, which is
the failure they later see out of domain. The mixing ratio is fixed at 1:1;
a sweep is listed as future work.''',
          ),
        ],
        messageStates: {
          'a1': MessageState(
            userMessageId: 'u1',
            sourceReferences: const [],
            runId: 'run-a1',
          ),
          'a2': MessageState(
            userMessageId: 'u2',
            sourceReferences: const [],
            runId: 'run-a2',
          ),
        },
      ),
      'evaluation': ThreadHistory(
        messages: [
          TextMessage(
            id: 'u3',
            user: ChatUser.user,
            createdAt: at(yesterday, 15, 30),
            text: 'Which papers discuss evaluation?',
          ),
          TextMessage(
            id: 'a3',
            user: ChatUser.assistant,
            createdAt: at(yesterday, 15, 42),
            text: 'Three of the indexed papers have a dedicated evaluation '
                'section: the two surveys and the retrieval paper. The surveys '
                'compare across BEIR; the retrieval paper reports only MS MARCO '
                'and Natural Questions.',
          ),
        ],
        messageStates: {
          'a3': MessageState(
            userMessageId: 'u3',
            sourceReferences: const [],
            runId: 'run-a3',
          ),
        },
      ),
      'untitled': ThreadHistory(messages: const []),
      'modules': ThreadHistory(
        messages: [
          TextMessage(
            id: 'u4',
            user: ChatUser.user,
            createdAt: at(yesterday, 11, 0),
            text: 'How does the module system work?',
          ),
          TextMessage(
            id: 'a4',
            user: ChatUser.assistant,
            createdAt: at(yesterday, 11, 20),
            text: '''
Each feature is an `AppModule`:

```dart
class LobbyAppModule extends AppModule {
  @override
  String get namespace => 'lobby';

  @override
  ModuleRoutes build() => ModuleRoutes(routes: [...]);
}
```

A `Flavor` lists the modules; `Flavor.build()` flattens their routes and
Riverpod overrides into one `ShellConfig`.''',
          ),
        ],
        messageStates: {
          'a4': MessageState(
            userMessageId: 'u4',
            sourceReferences: const [],
            runId: 'run-a4',
          ),
        },
      ),
    },
    documents: {
      'research': [
        RagDocument(
          id: 'doc-1',
          title: 'Dense Passage Retrieval Revisited',
          uri: 'papers/dpr-revisited.pdf',
          createdAt: yesterday.toUtc(),
        ),
        RagDocument(
          id: 'doc-2',
          title: 'A Survey of Neural Retrieval',
          uri: 'papers/survey-2024.pdf',
          createdAt: yesterday.toUtc(),
        ),
        RagDocument(
          id: 'doc-3',
          title: 'Evaluating Retrieval-Augmented Generation',
          uri: 'papers/rag-eval.pdf',
          createdAt: yesterday.toUtc(),
        ),
      ],
    },
  );
}
