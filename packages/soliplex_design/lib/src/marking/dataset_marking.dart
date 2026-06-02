/// Government dataset classification / control markings.
///
/// The enum members are ordered from least to most restrictive; that order
/// is also their [severity], which drives "highest applicable" computation
/// for aggregated or mixed views (see [highestOf]).
///
/// The [label] is the **authoritative** cue rendered by every marking
/// surface — color is only ever a secondary signal. Use [portionLabel] for
/// the parenthetical portion mark that precedes a sensitive section.
enum DatasetMarking {
  unclassified(label: 'UNCLASSIFIED', portion: 'U'),
  cui(label: 'CUI', portion: 'CUI'),
  confidential(label: 'CONFIDENTIAL', portion: 'C'),
  secret(label: 'SECRET', portion: 'S'),
  topSecret(label: 'TOP SECRET', portion: 'TS'),
  topSecretSci(label: 'TOP SECRET//SCI', portion: 'TS//SCI');

  const DatasetMarking({required this.label, required this.portion});

  /// Exact, authoritative banner/badge text (e.g. `TOP SECRET//SCI`).
  final String label;

  /// Short token used inside a portion mark (e.g. `S` → `(S)`).
  final String portion;

  /// Restrictiveness rank — higher is more restrictive. Equal to the
  /// declaration index.
  int get severity => index;

  /// The portion-marking prefix shown before a sensitive section, e.g.
  /// `(U)`, `(CUI)`, `(S)`.
  String get portionLabel => '($portion)';

  /// The most restrictive marking among [markings], for aggregated or
  /// mixed-marking views. Returns [DatasetMarking.unclassified] when empty.
  static DatasetMarking highestOf(Iterable<DatasetMarking> markings) {
    var highest = DatasetMarking.unclassified;
    for (final m in markings) {
      if (m.severity > highest.severity) highest = m;
    }
    return highest;
  }

  /// Whether [markings] contains more than one distinct marking — the
  /// trigger for a mixed-results warning.
  static bool isMixed(Iterable<DatasetMarking> markings) =>
      markings.toSet().length > 1;
}
