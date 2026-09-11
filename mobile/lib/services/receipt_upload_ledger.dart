import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/receipt_upload_task.dart';

// Local, per-device record of in-flight receipt uploads/analysis, since no
// local DB exists in this app and a handful of rows per batch doesn't
// warrant adding one. Backed by shared_preferences as a single JSON blob;
// ValueNotifier gives screens a simple way to rebuild when entries change.
class ReceiptUploadLedger {
  static const _prefsKey = 'receipt_upload_ledger';
  static const _maxAge = Duration(days: 7);

  final ValueNotifier<List<ReceiptUploadTask>> tasks = ValueNotifier([]);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as List;
      final loaded = decoded
          .map((e) => ReceiptUploadTask.fromJson(e as Map<String, dynamic>))
          .toList();
      final cutoff = DateTime.now().subtract(_maxAge);
      loaded.removeWhere((t) {
        final created = DateTime.tryParse(t.createdAt);
        return created != null && created.isBefore(cutoff);
      });
      tasks.value = loaded;
      await _persist();
    } catch (_) {
      // Corrupt/old-shape ledger: start fresh rather than crashing on it.
      tasks.value = [];
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(tasks.value.map((t) => t.toJson()).toList());
    await prefs.setString(_prefsKey, encoded);
  }

  ReceiptUploadTask? find(String localId) {
    for (final t in tasks.value) {
      if (t.localId == localId) return t;
    }
    return null;
  }

  List<ReceiptUploadTask> forBatch(String batchId) =>
      tasks.value.where((t) => t.batchId == batchId).toList();

  Future<void> upsert(ReceiptUploadTask task) async {
    final next = List<ReceiptUploadTask>.of(tasks.value);
    final idx = next.indexWhere((t) => t.localId == task.localId);
    if (idx >= 0) {
      next[idx] = task;
    } else {
      next.add(task);
    }
    tasks.value = next;
    await _persist();
  }

  // No-op (rather than throwing) if the entry is gone — an update can race
  // a removal (e.g. the entry was pruned right as a background isolate
  // delivers a stale status event for it).
  Future<void> update(
    String localId,
    ReceiptUploadTask Function(ReceiptUploadTask) transform,
  ) async {
    final current = find(localId);
    if (current == null) return;
    await upsert(transform(current));
  }

  Future<void> remove(String localId) async {
    final next = List<ReceiptUploadTask>.of(tasks.value)
      ..removeWhere((t) => t.localId == localId);
    if (next.length == tasks.value.length) return;
    tasks.value = next;
    await _persist();
  }
}
