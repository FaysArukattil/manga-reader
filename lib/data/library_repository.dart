import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/series.dart';

class LibrarySnapshot {
  const LibrarySnapshot(this.items, {required this.fromCache});
  final List<Series> items;
  final bool fromCache;
}

/// Firestore-backed shelf. Firestore's built-in offline persistence means the
/// shelf is readable offline and writes made offline sync automatically, so
/// no second local database is needed.
///
/// Writes are fire-and-forget on purpose: offline, Firestore only completes
/// the returned future once the server acknowledges, and the UI must never
/// wait on that.
class LibraryRepository {
  LibraryRepository(this.uid, {FirebaseFirestore? firestore})
      : _col = (firestore ?? FirebaseFirestore.instance)
            .collection('users')
            .doc(uid)
            .collection('series');

  final String uid;
  final CollectionReference<Map<String, dynamic>> _col;

  Stream<LibrarySnapshot> watch() => _col.snapshots().map(
        (s) => LibrarySnapshot(
          s.docs.map((d) => Series.fromMap(d.id, d.data())).toList(),
          fromCache: s.metadata.isFromCache,
        ),
      );

  String newId() => _col.doc().id;

  void add(Series series) => _fire(_col.doc(series.id).set(series.toMap()));

  /// [touch] bumps `updatedAt` (used for "last read" ordering).
  void update(String id, Map<String, Object?> fields, {bool touch = true}) {
    _fire(
      _col.doc(id).update({...fields, if (touch) 'updatedAt': Timestamp.now()}),
    );
  }

  void delete(String id) => _fire(_col.doc(id).delete());

  /// Deletes every series document for this user (account deletion).
  /// Needs a connection: batched deletes only complete once the server acks.
  Future<void> deleteAll() async {
    final snap = await _col.get();
    for (var i = 0; i < snap.docs.length; i += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs.skip(i).take(400)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  void _fire(Future<void> write) {
    write.catchError((Object e) {
      debugPrint('Firestore write failed: $e');
    });
  }
}
