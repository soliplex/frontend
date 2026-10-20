/// The datasets mockup's data model: what a dataset is, what its files go
/// through, and who can see it.
///
/// Mutable on purpose — the mockup's [DatasetsStore] edits these in place and
/// notifies — and nothing here is wired to the backend, which has no dataset
/// entity yet.
library;

import 'classification_levels.dart';

/// Where a committed file is on its way to being searchable.
enum FileStatus {
  /// Accepted and waiting for the ingestion run.
  queued,

  /// Being chunked and embedded.
  ingesting,

  /// In the dataset's database: the agent can search it.
  searchable,

  /// A type ingestion does not read (CSV, spreadsheets): the agent gets the
  /// raw file in its sandbox and nothing else, for good.
  sandboxOnly,
}

/// File extensions ingestion cannot read; the agent gets them as raw files.
const _rawOnlyExtensions = {'csv', 'xlsx', 'xls', 'parquet', 'json'};

String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

bool isIngestible(String name) =>
    !_rawOnlyExtensions.contains(extensionOf(name));

class DatasetFile {
  DatasetFile({
    required this.name,
    required this.sizeBytes,
    required this.level,
    required this.addedAt,
    FileStatus? status,
    this.progress = 0,
    this.outdated,
  }) : status = status ??
            (isIngestible(name)
                ? FileStatus.searchable
                : FileStatus.sandboxOnly);

  final String name;
  final int sizeBytes;

  /// The level the uploader declared for the file.
  final String level;
  final DateTime addedAt;
  FileStatus status;

  /// 0–1 while [FileStatus.ingesting].
  double progress;

  /// Set when someone has called the file out as wrong or outdated. Metadata
  /// only: the file stays indexed and searchable, and the agent is shown the
  /// mark beside anything it retrieves from the file.
  OutdatedMark? outdated;

  String get type => extensionOf(name).toUpperCase();
  bool get ingestible => status != FileStatus.sandboxOnly;
}

/// Why a file should no longer be trusted, and what to read instead.
///
/// Files can't be removed from a dataset, so this is the remedy for one that
/// is wrong or superseded: it flags the file, it doesn't take it out.
class OutdatedMark {
  const OutdatedMark({
    required this.reason,
    required this.by,
    required this.at,
    this.replacedBy,
  });

  final String reason;
  final String by;
  final DateTime at;

  /// The name of a file in the same dataset that supersedes this one.
  final String? replacedBy;
}

/// A dataset's state as a whole, derived from its files.
enum DatasetStatus {
  /// No files yet.
  empty,

  /// Some ingestible files are not searchable yet: the agent gets raw files
  /// only until they all are.
  ingesting,

  /// Every ingestible file is searchable.
  searchable,

  /// Only raw-only files: never searchable, always sandbox.
  sandboxOnly,
}

/// The tags a dataset needs before it can be shared — they are also what the
/// catalog filters on.
class DatasetTags {
  DatasetTags({
    Set<String>? keywords,
    Set<String>? affiliations,
    Set<String>? systems,
  })  : keywords = keywords ?? {},
        affiliations = affiliations ?? {},
        systems = systems ?? {};

  final Set<String> keywords;

  /// Division / site / team, written as a path
  /// ("Ops › Plant › Maintenance").
  final Set<String> affiliations;

  /// The equipment or system the dataset is about ("P-100").
  final Set<String> systems;

  /// The rule for sharing: a keyword, plus an affiliation or a system.
  bool get shareable =>
      keywords.isNotEmpty && (affiliations.isNotEmpty || systems.isNotEmpty);

  bool get isEmpty =>
      keywords.isEmpty && affiliations.isEmpty && systems.isEmpty;

  Iterable<String> get all => [...keywords, ...systems, ...affiliations];
}

/// Why a dataset should no longer be picked, and what to pick instead.
class Deprecation {
  const Deprecation({
    required this.reason,
    required this.by,
    required this.at,
    this.replacedById,
  });

  final String reason;
  final String by;
  final DateTime at;
  final String? replacedById;
}

class Dataset {
  Dataset({
    required this.namespace,
    required this.slug,
    required this.title,
    required this.level,
    required this.ownerId,
    required this.createdAt,
    this.description = '',
    DateTime? updatedAt,
    List<DatasetFile>? files,
    Set<String>? audience,
    DatasetTags? tags,
    this.deprecation,
    this.uses = 0,
  })  : updatedAt = updatedAt ?? createdAt,
        files = files ?? [],
        audience = audience ?? {},
        tags = tags ?? DatasetTags();

  final String namespace;
  final String slug;
  final String title;
  final String description;

  /// The highest level of information the dataset may hold. Fixed at
  /// creation: lowering it would void the screening its files went through.
  final String level;
  final String ownerId;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<DatasetFile> files;

  /// Principal ids (people and groups) it is shared with. Empty is private.
  Set<String> audience;
  DatasetTags tags;
  Deprecation? deprecation;

  /// How many threads use it — the catalog's "most used" order.
  final int uses;

  /// The namespaced label, which is also the dataset's id.
  String get id => label;
  String get label => '$namespace/$slug';

  bool get isShared => audience.isNotEmpty;
  bool get isDeprecated => deprecation != null;

  int get ingestibleTotal => files.where((f) => f.ingestible).length;
  int get ingestibleDone =>
      files.where((f) => f.status == FileStatus.searchable).length;
  int get outdatedCount => files.where((f) => f.outdated != null).length;
  int get sandboxOnlyCount =>
      files.where((f) => f.status == FileStatus.sandboxOnly).length;

  DatasetStatus get status {
    if (files.isEmpty) return DatasetStatus.empty;
    if (ingestibleTotal == 0) return DatasetStatus.sandboxOnly;
    return ingestibleDone == ingestibleTotal
        ? DatasetStatus.searchable
        : DatasetStatus.ingesting;
  }

  /// Whether a thread using it gets raw files without search.
  bool get isRawOnly =>
      status == DatasetStatus.ingesting || status == DatasetStatus.sandboxOnly;

  int get sizeBytes => files.fold(0, (sum, f) => sum + f.sizeBytes);
}

enum PrincipalKind { person, group }

/// Someone — or some group — a dataset can be shared with.
class Principal {
  const Principal({
    required this.id,
    required this.name,
    required this.kind,
    this.clearance,
    this.email,
    this.detail,
  });

  final String id;
  final String name;
  final PrincipalKind kind;

  /// People only: the highest level they may receive.
  final String? clearance;
  final String? email;

  /// A second line: a person's unit, a group's member count.
  final String? detail;
}

/// The signed-in user.
class MockUser {
  const MockUser({
    required this.person,
    required this.groupIds,
  });

  final Principal person;
  final Set<String> groupIds;

  String get id => person.id;
  String get clearance => person.clearance!;

  /// The personal namespace: the e-mail's local part.
  String get personalNamespace => person.email!.split('@').first;
}

/// A room as the deployer configured it: its level ceiling, and the datasets
/// a new thread starts with. Users can't edit or save these.
class RoomPreset {
  const RoomPreset({
    required this.roomId,
    required this.name,
    required this.description,
    required this.ceiling,
    required this.defaultDatasetIds,
    required this.skills,
  });

  final String roomId;
  final String name;
  final String description;
  final String ceiling;
  final List<String> defaultDatasetIds;
  final List<String> skills;
}

/// Whether [level] is at or below [ceiling].
bool isWithin(String level, String ceiling) =>
    levelRank(level) <= levelRank(ceiling);

/// The outcome of the upload scan for one staged file.
enum ScanStatus {
  /// Not scanned yet.
  pending,
  scanning,

  /// Nothing above the dataset's level found — advisory, not a determination.
  clean,

  /// Possible markings above the dataset's level: the uploader has to look.
  flagged,

  /// Declared above the dataset's level: it will not be added.
  rejected,

  /// A raw-only type: added, never searchable.
  sandboxOnly,
}

/// A file picked for upload, before it is committed.
class StagedFile {
  StagedFile({
    required this.name,
    required this.sizeBytes,
    required this.declaredLevel,
    this.simulatedFlag,
  });

  final String name;
  final int sizeBytes;
  String declaredLevel;

  /// What the simulated scan should find in it — the sample files carry one
  /// so the demo shows a flag without any real scanning.
  final String? simulatedFlag;

  ScanStatus status = ScanStatus.pending;
  String? advisory;

  /// The uploader looked at a flagged file and keeps it.
  bool acknowledged = false;

  /// Whether committing would add it.
  bool get included =>
      status == ScanStatus.clean ||
      status == ScanStatus.sandboxOnly ||
      (status == ScanStatus.flagged && acknowledged);
}
