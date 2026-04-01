# Citation Data Flow

## Overview

```text
Backend ask() → RAGState → JSON/SSE → Conversation.aguiState (raw)
→ CitationExtractor (schema firewall) → SourceReference (domain)
→ MessageState → buildSourceReferencesMap → CitationsSection
```

## Layer 1: Backend (Python)

File: `haiku/rag/skills/rag.py`

```python
class RAGState(BaseModel):
    citations: list[Citation] = []       # session-global flat list
    qa_history: list[QAHistoryEntry] = [] # per-turn Q&A pairs

class QAHistoryEntry(BaseModel):
    question: str
    answer: str
    confidence: float = 0.9
    citations: list[Citation] = []
```

The `ask()` skill sets `citation.index` (1-based, incremental across
session), appends to both `citations` and `qa_history`.

## Layer 2: AG-UI transport (JSON over SSE)

Two event types carry state:

- **StateSnapshotEvent**: full state as JSON
- **StateDeltaEvent**: RFC 6902 JSON Patch operations

Example payload:

```json
{
  "rag": {
    "qa_history": [
      {
        "question": "What is X?",
        "answer": "X is...",
        "citations": [
          {
            "index": 1,
            "chunk_id": "abc123",
            "document_id": "doc456",
            "document_uri": "s3://bucket/file.pdf",
            "document_title": "My Document",
            "content": "The relevant text...",
            "headings": ["Chapter 1", "Section 2"],
            "page_numbers": [5, 6]
          }
        ]
      }
    ],
    "citations": [ ... ],
    "citation_registry": { ... }
  }
}
```

## Layer 3: Frontend raw state

File: `packages/soliplex_client/lib/src/domain/conversation.dart`

```dart
class Conversation {
  final Map<String, dynamic> aguiState;       // raw JSON, not parsed
  final Map<String, MessageState> messageStates;
}
```

`aguiState` stays raw for diff-based extraction and forward
compatibility.

## Layer 4: Citation extraction

File:
`packages/soliplex_client/lib/src/application/citation_extractor.dart`

Called by `RunOrchestrator._extractCitations()` at run completion:

```dart
final citations = _citationExtractor.extractNew(
  _preRunAguiState,       // aguiState BEFORE this run
  conversation.aguiState, // aguiState AFTER this run
);
```

Algorithm: compare `qa_history` lengths, extract only new entries at
indices `[previousLength, currentLength)`, convert schema `Citation`
to domain `SourceReference`.

CitationExtractor is the **schema firewall** — the only file importing
generated types. Backend schema changes only affect this file.

## Layer 5: Domain model

```dart
// packages/soliplex_client/lib/src/domain/message_state.dart
class MessageState {
  final String userMessageId;
  final List<SourceReference> sourceReferences;
  final String? runId;
}

// packages/soliplex_client/lib/src/domain/source_reference.dart
class SourceReference {
  final String documentId;      // internal ID, not displayed
  final String documentUri;     // file path display
  final String content;         // markdown preview
  final String chunkId;         // chunk visualization API
  final String? documentTitle;  // via displayTitle extension
  final List<String> headings;  // breadcrumb
  final List<int> pageNumbers;  // via formattedPageNumbers extension
  final int? index;             // badge number (1-based from backend)
}
```

## Multi-run accumulation

In tool-yielding loops, `_preRunAguiState` tracks state before each
run segment. Each segment's new citations merge with existing ones:

```text
Run 1: extractNew({}, state1) → [sr1, sr2]
  _preRunAguiState = state1

Run 2: extractNew(state1, state2) → [sr3, sr4]
  merged = [sr1, sr2, sr3, sr4]
  _preRunAguiState = state2
```

Final `MessageState` carries all citations and the last segment's
`runId`.

## Type transformation

```text
Python Citation (snake_case) → JSON → Dart Citation (generated, camelCase)
→ SourceReference (frontend-owned, stable)
```

## File reference

| Purpose | File |
| ------- | ---- |
| Backend RAG state | `haiku/rag/skills/rag.py` |
| Event processing | `agui_event_processor.dart` |
| Conversation storage | `conversation.dart` |
| Citation extraction | `citation_extractor.dart` |
| Orchestrator coordination | `run_orchestrator.dart` |
| Generated schema | `haiku_rag_chat.dart` |
| Domain: citations | `source_reference.dart` |
| Domain: message metadata | `message_state.dart` |
