import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/mockups/datasets/model.dart';
import 'package:soliplex_frontend/src/mockups/datasets/sample_data.dart';
import 'package:soliplex_frontend/src/mockups/datasets/store.dart';
import 'package:soliplex_frontend/src/mockups/datasets/upload_session.dart';

void main() {
  late DatasetsStore store;

  setUp(() => store = sampleStore());
  tearDown(() => store.dispose());

  test('lists only datasets the user is cleared for and shared with', () {
    final ids = store.visible.map((d) => d.id).toSet();
    // Above jdoe's CONFIDENTIAL clearance.
    expect(ids, isNot(contains('ops/security-assessments-2026')));
    // Cleared, but not in the audience: clearance is not need-to-know.
    expect(ids, isNot(contains('eng/compressor-overhaul-planning')));
    // Shared with a group jdoe is in; and jdoe's own private dataset.
    expect(ids, contains('ops/pump-service-manuals'));
    expect(ids, contains('jdoe/inspection-notes'));
  });

  test('the catalog hides deprecated datasets until asked, and filters', () {
    expect(
      store.catalog().map((d) => d.id),
      isNot(contains('eng/legacy-pump-manuals-2019')),
    );
    store.updateQuery((q) => q.showDeprecated = true);
    expect(
      store.catalog().map((d) => d.id),
      contains('eng/legacy-pump-manuals-2019'),
    );

    store
      ..updateQuery((q) => q.text = 'pump')
      ..setFacet(Facet.system, 'P-100', selected: true)
      ..setFacet(Facet.level, 'internal', selected: true);
    final results = store.catalog();
    expect(results, isNotEmpty);
    expect(
      results.every(
          (d) => d.level == 'internal' && d.tags.systems.contains('P-100')),
      isTrue,
    );
  });

  test('the ceiling decides what a room may use', () {
    final confidential = store.byId('plant/shift-planning-playbook')!;
    final internal = store.byId('ops/pump-service-manuals')!;
    expect(store.isAboveCeiling(confidential, 'plant-mx'), isTrue);
    expect(store.isAboveCeiling(internal, 'plant-mx'), isFalse);
    expect(store.isAboveCeiling(confidential, 'ops-planning'), isFalse);
  });

  test('a new thread takes the room draft, which goes back to the defaults',
      () {
    store.addToTray('plant-mx', null, 'ops/maintenance-trend-data');
    expect(store.draftFor('plant-mx'), contains('ops/maintenance-trend-data'));

    final tray = store.trayFor('plant-mx', 'fresh-thread');
    expect(tray, contains('ops/maintenance-trend-data'));
    expect(
      store.draftFor('plant-mx'),
      presets.firstWhere((p) => p.roomId == 'plant-mx').defaultDatasetIds,
    );
    // Seeded threads keep their own.
    expect(store.trayFor('plant-mx', 'pump-pressure'), [
      'ops/pump-service-manuals',
      'jdoe/pump-quickref',
    ]);
  });

  test('committed files go through ingestion; rejected ones never land', () {
    fakeAsync((async) {
      final d = store.create(
        namespace: 'jdoe',
        slug: 'notes',
        title: 'Notes',
        description: '',
        level: 'internal',
      );
      final session = UploadSession(dataset: d)
        ..add(sampleUpload('internal'))
        ..startScan();
      async.elapse(const Duration(seconds: 10));
      expect(session.scanning, isFalse);
      expect(session.rejected, 1);
      expect(session.unresolved, 1);

      final flagged =
          session.files.firstWhere((f) => f.status == ScanStatus.flagged);
      session
        ..acknowledge(flagged, value: true)
        ..toReview();
      expect(session.canCommit, isFalse);
      session.attest(value: true);
      expect(session.canCommit, isTrue);

      store.commitUpload(d, session.files);
      expect(d.files, hasLength(5));
      expect(d.status, DatasetStatus.ingesting);
      expect(d.isRawOnly, isTrue);

      async.elapse(const Duration(seconds: 30));
      expect(d.status, DatasetStatus.searchable);
      expect(d.sandboxOnlyCount, 1);
      session.dispose();
    });
  });

  test('marking a file outdated keeps it searchable and can be undone', () {
    final d = store.byId('ops/pump-service-manuals')!;
    expect(d.outdatedCount, 1);
    final file = d.files.firstWhere((f) => f.outdated == null);
    store.markOutdated(d, file, reason: 'Wrong.', replacedBy: d.files[0].name);
    expect(d.outdatedCount, 2);
    expect(file.status, FileStatus.searchable);
    expect(d.files, contains(file));
    store.clearOutdated(file);
    expect(d.outdatedCount, 1);
  });

  test('sharing needs a keyword plus an affiliation or a system', () {
    expect(DatasetTags(keywords: {'a'}).shareable, isFalse);
    expect(DatasetTags(systems: {'P-100'}).shareable, isFalse);
    expect(DatasetTags(keywords: {'a'}, systems: {'P-100'}).shareable, isTrue);
    expect(
      DatasetTags(keywords: {'a'}, affiliations: {'Ops'}).shareable,
      isTrue,
    );
  });
}
