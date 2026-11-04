/// File-backed persistence adapter using `dart:io` for the Backend Server.
library;

import 'dart:io';
import 'announcement_repository.dart';

class FilePersistenceAdapter implements StoragePersistenceAdapter {
  final String storagePath;
  final String snapshotPath;

  FilePersistenceAdapter({
    this.storagePath = 'data/announcements_db.json',
    this.snapshotPath = 'data/announcements_snapshot.json',
  });

  @override
  String? readStateJson() {
    final file = File(storagePath);
    if (!file.existsSync()) return null;
    return file.readAsStringSync();
  }

  @override
  void writeStateJson(String jsonContent) {
    final file = File(storagePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonContent);
  }

  @override
  String? readSnapshotJson() {
    final file = File(snapshotPath);
    if (!file.existsSync()) return null;
    return file.readAsStringSync();
  }

  @override
  void writeSnapshotJson(String jsonContent) {
    final file = File(snapshotPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonContent);
  }
}

