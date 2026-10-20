import 'dart:async';

import 'package:flutter/foundation.dart';

import 'classification_levels.dart';
import 'model.dart';

enum UploadStep { choose, scan, review }

/// One upload into one dataset: the files picked, the simulated scan over
/// them, and what committing would add. Owned by the upload screen.
class UploadSession extends ChangeNotifier {
  UploadSession({
    required this.dataset,
    this.scanDelay = const Duration(milliseconds: 600),
  });

  final Dataset dataset;
  final Duration scanDelay;

  final List<StagedFile> files = [];
  UploadStep step = UploadStep.choose;
  bool attested = false;

  final List<Timer> _timers = [];

  void add(Iterable<StagedFile> picked) {
    files.addAll(picked);
    notifyListeners();
  }

  void remove(StagedFile file) {
    files.remove(file);
    notifyListeners();
  }

  void declare(StagedFile file, String level) {
    file.declaredLevel = level;
    notifyListeners();
  }

  void acknowledge(StagedFile file, {required bool value}) {
    file.acknowledged = value;
    notifyListeners();
  }

  void attest({required bool value}) {
    attested = value;
    notifyListeners();
  }

  bool get scanning => files.any(
        (f) =>
            f.status == ScanStatus.pending || f.status == ScanStatus.scanning,
      );

  /// Flags nobody has looked at yet.
  int get unresolved => files
      .where((f) => f.status == ScanStatus.flagged && !f.acknowledged)
      .length;

  Iterable<StagedFile> get included => files.where((f) => f.included);
  int get rejected =>
      files.where((f) => f.status == ScanStatus.rejected).length;
  int get sandboxOnly =>
      included.where((f) => f.status == ScanStatus.sandboxOnly).length;

  bool get canCommit => attested && included.isNotEmpty && unresolved == 0;

  /// Scans every file, one after another, so the results arrive the way a
  /// real scan's would — and the demo has something to watch.
  void startScan() {
    step = UploadStep.scan;
    for (final f in files) {
      f
        ..status = ScanStatus.pending
        ..acknowledged = false
        ..advisory = null;
    }
    notifyListeners();
    for (final (i, f) in files.indexed) {
      _timers
        ..add(
          Timer(scanDelay * i, () {
            f.status = ScanStatus.scanning;
            notifyListeners();
          }),
        )
        ..add(
          Timer(scanDelay * (i + 1), () {
            _finish(f);
            notifyListeners();
          }),
        );
    }
  }

  void _finish(StagedFile f) {
    final ceiling = dataset.level;
    if (!isWithin(f.declaredLevel, ceiling)) {
      f
        ..status = ScanStatus.rejected
        ..advisory = 'Declared ${levelLabel(f.declaredLevel)}, above this '
            "dataset's level (${levelLabel(ceiling)}). It won't be added.";
    } else if (f.simulatedFlag != null) {
      f
        ..status = ScanStatus.flagged
        ..advisory = f.simulatedFlag;
    } else if (!isIngestible(f.name)) {
      f
        ..status = ScanStatus.sandboxOnly
        ..advisory = "${extensionOf(f.name).toUpperCase()} isn't ingested for "
            'search; the agent can read it as a raw file.';
    } else {
      f
        ..status = ScanStatus.clean
        ..advisory = 'No markings above ${levelLabel(ceiling)} detected '
            '(advisory).';
    }
  }

  void toReview() {
    step = UploadStep.review;
    notifyListeners();
  }

  void back() {
    step = switch (step) {
      UploadStep.review => UploadStep.scan,
      _ => UploadStep.choose,
    };
    if (step == UploadStep.choose) _cancelScan();
    notifyListeners();
  }

  void _cancelScan() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    for (final f in files) {
      f.status = ScanStatus.pending;
    }
    attested = false;
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }
}

/// The files "Add sample files" stages: one of each outcome the scan has.
List<StagedFile> sampleUpload(String datasetLevel) => [
      StagedFile(
        name: 'pump-system-overview.pdf',
        sizeBytes: 4200000,
        declaredLevel: datasetLevel,
      ),
      StagedFile(
        name: 'torque-specs-rev-c.pdf',
        sizeBytes: 820000,
        declaredLevel: datasetLevel,
      ),
      StagedFile(
        name: 'shop-notes-2026.docx',
        sizeBytes: 96000,
        declaredLevel: datasetLevel,
      ),
      StagedFile(
        name: 'pump-failure-log.csv',
        sizeBytes: 310000,
        declaredLevel: datasetLevel,
      ),
      StagedFile(
        name: 'service-manual-excerpt.pdf',
        sizeBytes: 1500000,
        declaredLevel: datasetLevel,
        simulatedFlag: 'Possible CONFIDENTIAL markings on page 4 (advisory — '
            'not a determination). Review the file before keeping it.',
      ),
      StagedFile(
        name: 'ops-brief-peak.docx',
        sizeBytes: 240000,
        declaredLevel: 'confidential',
      ),
    ];
