import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;
import 'package:soliplex_frontend/src/modules/room/file_downloads.dart';

/// Downloads that save through [save], succeeding by default, disposed when
/// the test ends.
FileDownloads testDownloads([
  Future<DownloadOutcome> Function(WorkdirFile file)? save,
]) {
  final downloads = FileDownloads(save ?? (_) async => DownloadOutcome.success);
  addTearDown(downloads.dispose);
  return downloads;
}
