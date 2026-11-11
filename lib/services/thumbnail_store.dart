import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps one small JPEG preview per series on disk (never uploaded).
class ThumbnailStore {
  ThumbnailStore._(this._dir, this._ids);

  final Directory _dir;
  final Set<String> _ids;

  static Future<ThumbnailStore> create() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/thumbs');
    if (!await dir.exists()) await dir.create(recursive: true);
    final ids = <String>{};
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.jpg')) {
        final name = e.uri.pathSegments.last;
        ids.add(name.substring(0, name.length - 4));
      }
    }
    return ThumbnailStore._(dir, ids);
  }

  File? fileFor(String id) =>
      _ids.contains(id) ? File('${_dir.path}/$id.jpg') : null;

  Future<void> save(String id, Uint8List bytes) async {
    final file = File('${_dir.path}/$id.jpg');
    await file.writeAsBytes(bytes);
    _ids.add(id);
    await FileImage(file).evict();
  }

  Future<void> clear() async {
    final ids = _ids.toList();
    for (final id in ids) {
      await delete(id);
    }
  }

  Future<void> delete(String id) async {
    final file = File('${_dir.path}/$id.jpg');
    _ids.remove(id);
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
