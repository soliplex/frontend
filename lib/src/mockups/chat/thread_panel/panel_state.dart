import 'dart:async';

import 'package:flutter/widgets.dart';

import '../context_usage.dart';

/// Where a RAG database stands with this thread.
enum DbStatus { available, connecting, connected, indexing, unavailable }

/// A RAG database the thread can draw on.
class RagDatabase {
  const RagDatabase({
    required this.id,
    required this.name,
    required this.description,
    required this.documentCount,
    this.status = DbStatus.available,
  });

  final String id;
  final String name;
  final String description;
  final int documentCount;
  final DbStatus status;

  RagDatabase copyWith({DbStatus? status}) => RagDatabase(
        id: id,
        name: name,
        description: description,
        documentCount: documentCount,
        status: status ?? this.status,
      );
}

/// Basic skills ride on the auto-load switch; advanced ones load by hand.
enum SkillTier { basic, advanced }

enum SkillStatus { unloaded, loading, loaded }

/// A skill the agent can have in context.
class AgentSkill {
  const AgentSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.tier,
    required this.tokens,
    this.status = SkillStatus.unloaded,
  });

  final String id;
  final String name;
  final String description;
  final SkillTier tier;

  /// Roughly what loading it costs the context window.
  final int tokens;
  final SkillStatus status;

  AgentSkill copyWith({SkillStatus? status}) => AgentSkill(
        id: id,
        name: name,
        description: description,
        tier: tier,
        tokens: tokens,
        status: status ?? this.status,
      );
}

/// Someone a workspace note can go to.
class WorkspaceContact {
  const WorkspaceContact({required this.id, required this.name});

  final String id;
  final String name;

  String get initials {
    final parts = name.split(' ').where((p) => p.isNotEmpty);
    return parts.map((p) => p[0]).take(2).join().toUpperCase();
  }
}

/// A document a workspace note can embed.
class WorkspaceDocument {
  const WorkspaceDocument({required this.id, required this.title});

  final String id;
  final String title;
}

enum HandoffStatus { idle, generating, ready }

/// Everything the thread panel shows and changes, stubbed in memory.
///
/// Each "call" is a delayed state flip so the widgets can show their loading
/// states; nothing here reaches a backend. One instance per screen.
class ThreadPanelState extends ChangeNotifier {
  ThreadPanelState({
    required List<RagDatabase> databases,
    required List<AgentSkill> skills,
    required this.contacts,
    required this.documents,
    required ContextUsage contextUsage,
    this.autoLoadBasicSkills = true,
    Iterable<String> initialRecipients = const [],
  })  : _databases = List.of(databases),
        _skills = List.of(skills),
        _contextUsage = contextUsage,
        _recipientIds = {...initialRecipients};

  // ---- Panel chrome --------------------------------------------------------

  bool _open = true;
  bool get isOpen => _open;
  void toggleOpen() {
    _open = !_open;
    notifyListeners();
  }

  int _tab = 0;
  int get tab => _tab;
  set tab(int value) {
    if (_tab == value) return;
    _tab = value;
    notifyListeners();
  }

  // ---- Session state: what the panel looked like when it was last seen ----
  //
  // Held here rather than in widget state so it survives the panel being
  // torn down — collapsed on desktop, dismissed as a sheet on a phone. In
  // memory only, for as long as the screen lives.

  final Set<String> openSegments = {'databases'};
  bool isSegmentOpen(String id) => openSegments.contains(id);
  void toggleSegment(String id) {
    if (!openSegments.remove(id)) openSegments.add(id);
    notifyListeners();
  }

  final Set<String> expandedRows = {};
  bool isRowExpanded(String id) => expandedRows.contains(id);
  void toggleRow(String id) {
    if (!expandedRows.remove(id)) expandedRows.add(id);
    notifyListeners();
  }

  final Map<String, ScrollController> _scrolls = {};
  final Map<String, double> _scrollOffsets = {};

  /// A scroll controller for the list named [key] that resumes where that
  /// list was last left. A controller whose list has gone (the panel was
  /// dismissed) is replaced by one starting at the remembered offset.
  ScrollController scrollFor(String key) {
    final existing = _scrolls[key];
    if (existing != null && existing.hasClients) return existing;
    existing?.dispose();
    final controller = ScrollController(
      initialScrollOffset: _scrollOffsets[key] ?? 0,
    );
    controller.addListener(() {
      if (controller.hasClients) _scrollOffsets[key] = controller.offset;
    });
    return _scrolls[key] = controller;
  }

  /// The workspace draft, kept across a dismissed sheet.
  final noteTitle = TextEditingController();
  final noteContent = TextEditingController();

  // ---- Databases -----------------------------------------------------------

  final List<RagDatabase> _databases;
  List<RagDatabase> get databases => List.unmodifiable(_databases);

  int get connectedDatabaseCount =>
      _databases.where((d) => d.status == DbStatus.connected).length;

  void toggleDatabase(String id) {
    final i = _databases.indexWhere((d) => d.id == id);
    if (i < 0) return;
    final db = _databases[i];
    switch (db.status) {
      case DbStatus.available:
        _databases[i] = db.copyWith(status: DbStatus.connecting);
        notifyListeners();
        _later(const Duration(milliseconds: 900), () {
          _databases[i] = db.copyWith(status: DbStatus.connected);
          _bumpContext(ContextShare.rag, db.documentCount * 3);
        });
      case DbStatus.connected:
        _databases[i] = db.copyWith(status: DbStatus.available);
        _bumpContext(ContextShare.rag, -db.documentCount * 3);
      case DbStatus.connecting:
      case DbStatus.indexing:
      case DbStatus.unavailable:
        break;
    }
    notifyListeners();
  }

  // ---- Skills --------------------------------------------------------------

  final List<AgentSkill> _skills;
  List<AgentSkill> get skills => List.unmodifiable(_skills);

  bool autoLoadBasicSkills;

  /// What is in context right now: basic skills when auto-load is on, plus
  /// every advanced skill loaded by hand.
  List<AgentSkill> get loadedSkills => [
        for (final s in _skills)
          if (s.tier == SkillTier.basic
              ? autoLoadBasicSkills
              : s.status == SkillStatus.loaded)
            s,
      ];

  List<AgentSkill> get advancedSkills =>
      _skills.where((s) => s.tier == SkillTier.advanced).toList();

  void setAutoLoadBasicSkills(bool value) {
    if (autoLoadBasicSkills == value) return;
    autoLoadBasicSkills = value;
    final basicTokens = _skills
        .where((s) => s.tier == SkillTier.basic)
        .fold(0, (sum, s) => sum + s.tokens);
    _bumpContext(ContextShare.system, value ? basicTokens : -basicTokens);
    notifyListeners();
  }

  void toggleSkill(String id) {
    final i = _skills.indexWhere((s) => s.id == id);
    if (i < 0) return;
    final skill = _skills[i];
    switch (skill.status) {
      case SkillStatus.unloaded:
        _skills[i] = skill.copyWith(status: SkillStatus.loading);
        notifyListeners();
        _later(const Duration(milliseconds: 700), () {
          _skills[i] = skill.copyWith(status: SkillStatus.loaded);
          _bumpContext(ContextShare.system, skill.tokens);
        });
      case SkillStatus.loaded:
        _skills[i] = skill.copyWith(status: SkillStatus.unloaded);
        _bumpContext(ContextShare.system, -skill.tokens);
        notifyListeners();
      case SkillStatus.loading:
        break;
    }
  }

  // ---- Context usage -------------------------------------------------------

  ContextUsage _contextUsage;
  ContextUsage get contextUsage => _contextUsage;

  HandoffStatus _handoff = HandoffStatus.idle;
  HandoffStatus get handoffStatus => _handoff;
  String? _handoffText;
  String? get handoffText => _handoffText;

  /// Pretends to ask the model for a summary of the thread so far.
  void generateHandoff() {
    if (_handoff == HandoffStatus.generating) return;
    _handoff = HandoffStatus.generating;
    notifyListeners();
    _later(const Duration(milliseconds: 1600), () {
      _handoff = HandoffStatus.ready;
      _handoffText = _sampleHandoff;
      _bumpContext(ContextShare.llm, 420);
    });
  }

  void clearHandoff() {
    _handoff = HandoffStatus.idle;
    _handoffText = null;
    notifyListeners();
  }

  /// Moves the reading by [delta] tokens, attributed to [share].
  void _bumpContext(ContextShare share, int delta) {
    _contextUsage = _contextUsage.adding(share, delta);
  }

  // ---- Workspace -----------------------------------------------------------

  final List<WorkspaceContact> contacts;
  final List<WorkspaceDocument> documents;

  final Set<String> _recipientIds;
  List<WorkspaceContact> get recipients =>
      contacts.where((c) => _recipientIds.contains(c.id)).toList();
  bool isRecipient(String id) => _recipientIds.contains(id);
  void toggleRecipient(String id) {
    if (!_recipientIds.remove(id)) _recipientIds.add(id);
    notifyListeners();
  }

  final Set<String> _embeddedIds = {};
  List<WorkspaceDocument> get embeddedDocuments =>
      documents.where((d) => _embeddedIds.contains(d.id)).toList();
  bool isEmbedded(String id) => _embeddedIds.contains(id);
  void toggleEmbedded(String id) {
    if (!_embeddedIds.remove(id)) _embeddedIds.add(id);
    notifyListeners();
  }

  int _sentCount = 0;
  int get sentCount => _sentCount;

  /// Pretends to deliver the note and resets the form.
  void sendNote() {
    _sentCount++;
    _recipientIds.clear();
    _embeddedIds.clear();
    noteTitle.clear();
    noteContent.clear();
    notifyListeners();
  }

  // ---- Plumbing ------------------------------------------------------------

  final List<Timer> _timers = [];

  void _later(Duration delay, VoidCallback body) {
    _timers.add(Timer(delay, () {
      body();
      notifyListeners();
    }));
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    for (final c in _scrolls.values) {
      c.dispose();
    }
    noteTitle.dispose();
    noteContent.dispose();
    super.dispose();
  }
}

const _sampleHandoff = '''
**Thread so far**

The user asked for a summary of the corpus's most recent retrieval paper
("Dense Passage Retrieval Revisited", 2025) and then for detail on its hard
negatives.

**Established**
- A single dense encoder with hard negatives matches hybrid systems in domain;
  the gap reopens out of domain, attributed to vocabulary shift.
- Hard negatives are a 1:1 mix of BM25 negatives and in-batch negatives; the
  ratio was not swept.
- Cross-encoder re-ranking of the top 20 recovers most of the out-of-domain
  gap at ~3× latency.

**Open**
- The user has not yet asked how this compares to the survey's numbers.

**Sources in context**: Dense Passage Retrieval Revisited (pp. 3–7).''';
