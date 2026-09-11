import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../api/receipt_api.dart';
import '../models/receipt_upload_task.dart';
import 'receipt_upload_ledger.dart';

// Drives receipt image uploads through background_downloader so they keep
// running (and are resumed by the OS) after the app is backgrounded or
// terminated — a plain http.MultipartRequest's Future is gone the moment
// the process is suspended. Each picked image becomes one UploadTask;
// analysis itself happens server-side once the image lands (see the
// backend's async receipt_jobs pipeline), so this manager's only job is to
// get the bytes there reliably and track progress for the UI.
class ReceiptUploadManager {
  ReceiptUploadManager._();
  static final ReceiptUploadManager instance = ReceiptUploadManager._();

  static const _uploadsDirName = 'receipt_uploads';
  static const _uuid = Uuid();

  final ReceiptUploadLedger ledger = ReceiptUploadLedger();

  String? _baseUrl;
  bool _initialized = false;

  Future<void> init(String baseUrl) async {
    if (_initialized) return;
    _initialized = true;
    _baseUrl = baseUrl;

    await ledger.load();
    FileDownloader().updates.listen(_onUpdate);
    // Replays any status/progress events the OS delivered while the app
    // wasn't running to receive them.
    await FileDownloader().resumeFromBackground();
    await _configureNotifications();
  }

  Future<void> _configureNotifications() async {
    FileDownloader().configureNotification(
      running: const TaskNotification('Uploading receipts', '{filename}'),
      complete: const TaskNotification('Receipts uploaded', 'Tap to review'),
      error: const TaskNotification('Receipt upload failed', '{filename}'),
      progressBar: true,
      groupNotificationId: 'receipt-uploads',
    );
    try {
      final status = await FileDownloader().permissions.status(PermissionType.notifications);
      if (status != PermissionStatus.granted) {
        await FileDownloader().permissions.request(PermissionType.notifications);
      }
    } catch (_) {
      // Best-effort — uploads still work without notification permission,
      // the user just won't see progress while the app is backgrounded.
    }
  }

  // Copies [file] into the app's persistent support directory (image_picker's
  // temp path isn't guaranteed to survive until a queued upload actually
  // runs, especially if it's retried later on a network reconnect), records
  // a queued ledger entry, and enqueues the background upload task.
  Future<String> enqueueFile(File file, {required String batchId}) async {
    final localId = _uuid.v4();
    final ext = p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path);
    final filename = '$localId$ext';

    final dir = await _uploadsDirectory();
    await file.copy(p.join(dir.path, filename));

    await ledger.upsert(ReceiptUploadTask(
      localId: localId,
      batchId: batchId,
      filename: filename,
      status: ReceiptUploadStatus.queued,
      createdAt: DateTime.now().toIso8601String(),
    ));

    await _enqueueUploadTask(taskId: localId, batchId: batchId, filename: filename);
    return localId;
  }

  Future<void> _enqueueUploadTask({
    required String taskId,
    required String batchId,
    required String filename,
  }) async {
    final task = UploadTask(
      taskId: taskId,
      url: '$_baseUrl/receipts/jobs',
      filename: filename,
      baseDirectory: BaseDirectory.applicationSupport,
      directory: _uploadsDirName,
      fileField: 'image',
      mimeType: _mimeTypeFor(filename),
      fields: {'batch_id': batchId},
      updates: Updates.statusAndProgress,
      retries: 3,
      group: 'receipt-uploads',
    );
    await FileDownloader().enqueue(task);
  }

  // Re-enqueues an image whose upload itself never reached the server (no
  // receipt_jobs row exists yet, so there's nothing to resume server-side).
  Future<void> retryUpload(String localId) async {
    final entry = ledger.find(localId);
    if (entry == null) return;
    await ledger.upsert(entry.copyWith(
      status: ReceiptUploadStatus.queued,
      progress: 0,
      clearError: true,
    ));
    await _enqueueUploadTask(taskId: localId, batchId: entry.batchId, filename: entry.filename);
  }

  // Retries a job that uploaded fine but failed server-side analysis — the
  // server already has the bytes, so this just flips it back to queued
  // there instead of re-uploading.
  Future<void> retryAnalysis(String localId, ReceiptApi api) async {
    final entry = ledger.find(localId);
    if (entry?.jobId == null) return;
    await api.retryJob(entry!.jobId!);
    await ledger.upsert(entry.copyWith(
      status: ReceiptUploadStatus.uploaded,
      clearError: true,
    ));
  }

  Future<File> fileFor(ReceiptUploadTask entry) async {
    final dir = await _uploadsDirectory();
    return File(p.join(dir.path, entry.filename));
  }

  void _onUpdate(TaskUpdate update) {
    final localId = update.task.taskId;
    if (update is TaskStatusUpdate) {
      switch (update.status) {
        case TaskStatus.enqueued:
        case TaskStatus.running:
        case TaskStatus.waitingToRetry:
          ledger.update(localId, (e) => e.copyWith(status: ReceiptUploadStatus.uploading));
        case TaskStatus.complete:
          _handleUploadComplete(localId, update.responseBody);
        case TaskStatus.failed:
        case TaskStatus.notFound:
        case TaskStatus.canceled:
          ledger.update(
            localId,
            (e) => e.copyWith(
              status: ReceiptUploadStatus.uploadFailed,
              error: update.exception?.description ?? 'Upload failed',
            ),
          );
        case TaskStatus.paused:
          break;
      }
    } else if (update is TaskProgressUpdate) {
      final clamped = update.progress.clamp(0, 1).toDouble();
      ledger.update(localId, (e) => e.copyWith(progress: clamped));
    }
  }

  void _handleUploadComplete(String localId, String? responseBody) {
    int? jobId;
    if (responseBody != null) {
      try {
        final decoded = jsonDecode(responseBody);
        if (decoded is Map && decoded['id'] is num) {
          jobId = (decoded['id'] as num).toInt();
        }
      } catch (_) {
        // Unexpected body shape — jobId stays null; ListJobs polling from
        // GET /receipts/jobs still works once the batch is queried as a
        // whole, this just means this entry can't be looked up individually.
      }
    }
    ledger.update(
      localId,
      (e) => e.copyWith(status: ReceiptUploadStatus.uploaded, jobId: jobId, progress: 1),
    );
  }

  Future<Directory> _uploadsDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, _uploadsDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _mimeTypeFor(String filename) {
    switch (p.extension(filename).toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}
