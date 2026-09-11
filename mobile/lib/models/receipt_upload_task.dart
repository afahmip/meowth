// A locally-tracked entry for one image on the background upload+analyze
// pipeline (see ReceiptUploadManager). Once a job's server-side analysis
// finishes successfully, its entry is dropped from the ledger — the
// resulting receipt already shows up via the existing GET /receipts list
// (PendingReceiptsScreen), so there's no need to keep tracking it locally.
enum ReceiptUploadStatus { queued, uploading, uploaded, uploadFailed, analysisFailed }

ReceiptUploadStatus _statusFromJson(String s) => ReceiptUploadStatus.values.firstWhere(
      (v) => v.name == s,
      orElse: () => ReceiptUploadStatus.queued,
    );

class ReceiptUploadTask {
  // Stable local identity; doubles as the background_downloader taskId for
  // as long as this entry is on its first (or a retried) upload attempt.
  final String localId;
  final String batchId;
  // Filename within the app's persistent "receipt_uploads" directory (see
  // ReceiptUploadManager) — not an absolute path, since the app's sandbox
  // path can change between installs/updates.
  final String filename;
  final ReceiptUploadStatus status;
  final double progress;
  final int? jobId;
  final String? error;
  final String createdAt;

  const ReceiptUploadTask({
    required this.localId,
    required this.batchId,
    required this.filename,
    required this.status,
    this.progress = 0,
    this.jobId,
    this.error,
    required this.createdAt,
  });

  ReceiptUploadTask copyWith({
    ReceiptUploadStatus? status,
    double? progress,
    int? jobId,
    String? error,
    bool clearError = false,
  }) =>
      ReceiptUploadTask(
        localId: localId,
        batchId: batchId,
        filename: filename,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        jobId: jobId ?? this.jobId,
        error: clearError ? null : (error ?? this.error),
        createdAt: createdAt,
      );

  factory ReceiptUploadTask.fromJson(Map<String, dynamic> j) => ReceiptUploadTask(
        localId: j['local_id'],
        batchId: j['batch_id'],
        filename: j['filename'],
        status: _statusFromJson(j['status'] ?? ''),
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        jobId: j['job_id'],
        error: j['error'],
        createdAt: j['created_at'] ?? DateTime.now().toIso8601String(),
      );

  Map<String, dynamic> toJson() => {
        'local_id': localId,
        'batch_id': batchId,
        'filename': filename,
        'status': status.name,
        'progress': progress,
        'job_id': jobId,
        'error': error,
        'created_at': createdAt,
      };
}
