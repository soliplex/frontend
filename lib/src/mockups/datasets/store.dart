import 'dart:async';

import 'package:flutter/widgets.dart';

import 'classification_levels.dart';
import 'model.dart';

enum CatalogSort {
  updated('Recently updated'),
  name('Name'),
  uses('Most used');

  const CatalogSort(this.label);
  final String label;
}

/// A catalog facet: one way to narrow the list.
enum Facet {
  level('Level'),
  namespace('Namespace'),
  owner('Owner'),
  keyword('Keywords'),
  system('System'),
  affiliation('Affiliation');

  const Facet(this.label);
  final String label;
}

/// What the catalog is showing. Held by the store so the filters survive
/// leaving the catalog for a dataset and coming back.
class CatalogQuery {
  String text = '';
  final Map<Facet, Set<String>> selected = {
    for (final f in Facet.values) f: {}
  };
  bool searchableOnly = false;
  bool showDeprecated = false;
  CatalogSort sort = CatalogSort.updated;

  int get activeCount =>
      selected.values.fold(0, (n, s) => n + s.length) +
      (searchableOnly ? 1 : 0) +
      (showDeprecated ? 1 : 0);

  void clear() {
    for (final s in selected.values) {
      s.clear();
    }
    searchableOnly = false;
    showDeprecated = false;
  }
}

/// Everything the datasets mockup knows, in memory, with the simulated
/// ingestion that moves committed files along.
///
/// One per mockup, above its router, so every screen reads the same datasets
/// and a hot restart starts over.
class DatasetsStore extends ChangeNotifier {
  DatasetsStore({
    required this.user,
    required List<Principal> principals,
    required List<Dataset> datasets,
    required this.orgNamespaces,
    required List<RoomPreset> presets,
    Map<String, List<String>> trays = const {},
    Set<String> pinned = const {},
    this.ingestTick = const Duration(milliseconds: 350),
  })  : principals = {for (final p in principals) p.id: p},
        _datasets = datasets,
        presets = {for (final p in presets) p.roomId: p},
        _trays = {
          for (final e in trays.entries) e.key: [...e.value]
        },
        _pinned = {...pinned};

  final MockUser user;
  final Map<String, Principal> principals;
  final List<Dataset> _datasets;

  /// The organisation namespaces the deployer configured.
  final List<String> orgNamespaces;
  final Map<String, RoomPreset> presets;
  final Duration ingestTick;

  final query = CatalogQuery();

  // ---- Access ------------------------------------------------------------

  /// Cleared for its level, and the owner or in its audience — directly or
  /// through a group. Clearance alone is not need-to-know.
  bool canAccess(Dataset d) {
    if (levelRank(user.clearance) < levelRank(d.level)) return false;
    if (d.ownerId == user.id) return true;
    return d.audience.contains(user.id) ||
        d.audience.any(user.groupIds.contains);
  }

  bool isOwner(Dataset d) => d.ownerId == user.id;

  /// Every dataset the user may know exists. The rest are never listed.
  Iterable<Dataset> get visible => _datasets.where(canAccess);

  Dataset? byId(String id) {
    for (final d in _datasets) {
      if (d.id == id) return d;
    }
    return null;
  }

  String ownerName(Dataset d) => principals[d.ownerId]?.name ?? d.ownerId;

  List<String> get namespaces => [user.personalNamespace, ...orgNamespaces];

  // ---- Catalog -----------------------------------------------------------

  /// The catalog as [query] filters and orders it.
  List<Dataset> catalog({String? ceiling, bool withinCeiling = false}) {
    final results = _textMatches().where((d) {
      if (!query.showDeprecated && d.isDeprecated) return false;
      if (query.searchableOnly && d.status != DatasetStatus.searchable) {
        return false;
      }
      if (withinCeiling && ceiling != null && !isWithin(d.level, ceiling)) {
        return false;
      }
      for (final facet in Facet.values) {
        final wanted = query.selected[facet]!;
        if (wanted.isEmpty) continue;
        if (!facetValues(facet, d).any(wanted.contains)) return false;
      }
      return true;
    }).toList();
    switch (query.sort) {
      case CatalogSort.updated:
        results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case CatalogSort.name:
        results.sort((a, b) => a.label.compareTo(b.label));
      case CatalogSort.uses:
        results.sort((a, b) => b.uses.compareTo(a.uses));
    }
    return results;
  }

  Iterable<Dataset> _textMatches() {
    final text = query.text.trim().toLowerCase();
    if (text.isEmpty) return visible;
    return visible.where(
      (d) => [d.label, d.title, d.description, ...d.tags.all]
          .any((s) => s.toLowerCase().contains(text)),
    );
  }

  Iterable<String> facetValues(Facet facet, Dataset d) => switch (facet) {
        Facet.level => [d.level],
        Facet.namespace => [d.namespace],
        Facet.owner => [d.ownerId],
        Facet.keyword => d.tags.keywords,
        Facet.system => d.tags.systems,
        Facet.affiliation => d.tags.affiliations,
      };

  /// Each value of [facet] among the datasets the search text matches, with
  /// how many carry it, most common first. Levels keep their severity order.
  List<(String, int)> facetCounts(Facet facet) {
    final counts = <String, int>{};
    for (final d in _textMatches()) {
      if (!query.showDeprecated && d.isDeprecated) continue;
      for (final v in facetValues(facet, d)) {
        counts[v] = (counts[v] ?? 0) + 1;
      }
    }
    final entries = [for (final e in counts.entries) (e.key, e.value)];
    if (facet == Facet.level) {
      entries.sort((a, b) => levelRank(a.$1).compareTo(levelRank(b.$1)));
    } else {
      entries.sort((a, b) => b.$2.compareTo(a.$2));
    }
    return entries;
  }

  /// What to show for a facet value: owners by name, levels by marking.
  String facetLabel(Facet facet, String value) => switch (facet) {
        Facet.owner => principals[value]?.name ?? value,
        Facet.level => levelLabel(value),
        _ => value,
      };

  void setFacet(Facet facet, String value, {required bool selected}) {
    final set = query.selected[facet]!;
    selected ? set.add(value) : set.remove(value);
    notifyListeners();
  }

  void updateQuery(void Function(CatalogQuery q) change) {
    change(query);
    notifyListeners();
  }

  /// Values already used for a kind of tag, for the tag fields to suggest —
  /// free text stays consistent when the common spellings are one tap away.
  List<String> tagSuggestions(Facet facet) {
    final counts = <String, int>{};
    for (final d in _datasets) {
      for (final v in facetValues(facet, d)) {
        counts[v] = (counts[v] ?? 0) + 1;
      }
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  // ---- Pins --------------------------------------------------------------

  final Set<String> _pinned;
  bool isPinned(String id) => _pinned.contains(id);
  List<Dataset> get pinned =>
      [for (final id in _pinned) byId(id)].nonNulls.where(canAccess).toList();

  void togglePin(String id) {
    _pinned.contains(id) ? _pinned.remove(id) : _pinned.add(id);
    notifyListeners();
  }

  // ---- Rooms and threads -------------------------------------------------

  /// Thread id → the datasets it uses. Fixed once the thread has messages.
  final Map<String, List<String>> _trays;

  /// Room id → the datasets the next thread in it will start with.
  final Map<String, List<String>> _drafts = {};

  RoomPreset? preset(String roomId) => presets[roomId];

  bool isAboveCeiling(Dataset d, String roomId) {
    final p = presets[roomId];
    return p != null && !isWithin(d.level, p.ceiling);
  }

  /// The datasets a new thread in [roomId] will start with: the room's
  /// defaults, as edited since.
  List<String> draftFor(String roomId) => _drafts.putIfAbsent(
        roomId,
        () => [...?presets[roomId]?.defaultDatasetIds],
      );

  /// The datasets [threadId] uses — or, with no thread, the draft for the
  /// next one.
  ///
  /// A thread seen for the first time was just spawned by a send from the
  /// room's welcome composer, so it takes the draft, and the draft goes back
  /// to the room's defaults. Called from build, so it records without
  /// notifying: nothing anyone sees changes.
  List<String> trayFor(String roomId, String? threadId) {
    if (threadId == null) return draftFor(roomId);
    return _trays.putIfAbsent(threadId, () {
      final adopted = [...draftFor(roomId)];
      _drafts.remove(roomId);
      return adopted;
    });
  }

  void addToTray(String roomId, String? threadId, String datasetId) {
    final tray = trayFor(roomId, threadId);
    if (!tray.contains(datasetId)) tray.add(datasetId);
    notifyListeners();
  }

  void removeFromTray(String roomId, String? threadId, String datasetId) {
    trayFor(roomId, threadId).remove(datasetId);
    notifyListeners();
  }

  /// Starts the room's next thread from [ids] — the way out of a thread whose
  /// datasets are fixed.
  void startNewThreadWith(String roomId, List<String> ids) {
    _drafts[roomId] = [...ids];
    notifyListeners();
  }

  // ---- Lifecycle ---------------------------------------------------------

  Dataset create({
    required String namespace,
    required String slug,
    required String title,
    required String description,
    required String level,
    DatasetTags? tags,
  }) {
    final now = DateTime.now();
    final dataset = Dataset(
      namespace: namespace,
      slug: slug,
      title: title,
      description: description,
      level: level,
      ownerId: user.id,
      createdAt: now,
      tags: tags,
    );
    _datasets.add(dataset);
    notifyListeners();
    return dataset;
  }

  bool labelTaken(String namespace, String slug) =>
      byId('$namespace/$slug') != null;

  /// Adds the files the scan let through and schedules their ingestion.
  void commitUpload(Dataset d, Iterable<StagedFile> staged) {
    final now = DateTime.now();
    final added = <DatasetFile>[];
    for (final s in staged.where((s) => s.included)) {
      added.add(
        DatasetFile(
          name: s.name,
          sizeBytes: s.sizeBytes,
          level: s.declaredLevel,
          addedAt: now,
          status:
              isIngestible(s.name) ? FileStatus.queued : FileStatus.sandboxOnly,
        ),
      );
    }
    d
      ..files.addAll(added)
      ..updatedAt = now;
    notifyListeners();
    _scheduleIngestion(added);
  }

  void share(Dataset d, Set<String> audience, DatasetTags tags) {
    d
      ..audience = {...audience}
      ..tags = tags
      ..updatedAt = DateTime.now();
    notifyListeners();
  }

  void deprecate(Dataset d, {required String reason, String? replacedById}) {
    d.deprecation = Deprecation(
      reason: reason,
      by: user.id,
      at: DateTime.now(),
      replacedById: replacedById,
    );
    notifyListeners();
  }

  void markOutdated(
    Dataset d,
    DatasetFile f, {
    required String reason,
    String? replacedBy,
  }) {
    f.outdated = OutdatedMark(
      reason: reason,
      by: user.id,
      at: DateTime.now(),
      replacedBy: replacedBy,
    );
    notifyListeners();
  }

  void clearOutdated(DatasetFile f) {
    f.outdated = null;
    notifyListeners();
  }

  // ---- Simulated ingestion -----------------------------------------------

  Timer? _ingest;

  /// Moves queued files through ingestion, a couple at a time, for as long as
  /// there are any. Only files committed in this session move: seeded
  /// datasets that are mid-ingestion stay where the sample data put them, so
  /// the mockup has a resting state.
  final Set<DatasetFile> _moving = {};

  void _scheduleIngestion(Iterable<DatasetFile> added) {
    _moving.addAll(added.where((f) => f.status == FileStatus.queued));
    if (_moving.isEmpty) return;
    _ingest ??= Timer.periodic(ingestTick, (_) => _advance());
  }

  void _advance() {
    final active =
        _moving.where((f) => f.status == FileStatus.ingesting).toList();
    for (final f in active) {
      f.progress += 0.34;
      if (f.progress >= 1) {
        f
          ..progress = 1
          ..status = FileStatus.searchable;
        _moving.remove(f);
      }
    }
    final slots =
        2 - _moving.where((f) => f.status == FileStatus.ingesting).length;
    for (final f in _moving
        .where((f) => f.status == FileStatus.queued)
        .take(slots)
        .toList()) {
      f
        ..status = FileStatus.ingesting
        ..progress = 0;
    }
    if (_moving.isEmpty) {
      _ingest?.cancel();
      _ingest = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ingest?.cancel();
    super.dispose();
  }
}

/// Makes the [DatasetsStore] reachable from every route of the mockup, and
/// rebuilds whoever reads it when it changes.
class DatasetsScope extends InheritedNotifier<DatasetsStore> {
  const DatasetsScope({
    required DatasetsStore store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static DatasetsStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DatasetsScope>()!.notifier!;

  /// For callbacks: reads without subscribing.
  static DatasetsStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DatasetsScope>()!.notifier!;
}
