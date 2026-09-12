import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../api/receipt_api.dart';
import '../config.dart';
import '../models/receipt.dart';
import '../models/receipt_upload_task.dart';
import '../services/receipt_upload_manager.dart';
import '../widgets/shimmer_placeholder.dart';
import 'receipt_upload_screen.dart';

// Doubles as the "batch progress" view from the async upload RFC: on top of
// the server-side unsaved receipts GET /receipts already returns, it shows
// ReceiptUploadManager's local ledger of images still uploading or being
// analyzed. A ledger entry is removed once its job reaches "done" — from
// that point the finished receipt is already present in the GET /receipts
// list below, so there's nothing left for the ledger to track.
class PendingReceiptsScreen extends StatefulWidget {
  const PendingReceiptsScreen({super.key});

  @override
  State<PendingReceiptsScreen> createState() => _PendingReceiptsScreenState();
}

class _PendingReceiptsScreenState extends State<PendingReceiptsScreen> {
  late final ReceiptApi _api;
  final _uploadManager = ReceiptUploadManager.instance;
  Timer? _pollTimer;
  List<ReceiptListItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = ReceiptApi(AppConfig.baseUrl);
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollUploadedJobs());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await _api.list();
      setState(() => _items = all.where((r) => !r.isSaved).toList());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  // Polls GET /receipts/jobs for every ledger entry whose upload finished
  // (jobId known) but whose server-side analysis hasn't resolved yet. A job
  // reaching "done" is dropped from the ledger and folded into a reload of
  // the regular pending-receipts list; a job reaching "failed" is kept in
  // the ledger so its Retry action stays visible.
  Future<void> _pollUploadedJobs() async {
    final uploaded = _uploadManager.ledger.tasks.value
        .where((t) => t.status == ReceiptUploadStatus.uploaded && t.jobId != null)
        .toList();
    if (uploaded.isEmpty) return;

    final batchIds = uploaded.map((t) => t.batchId).toSet();
    var anyDone = false;
    for (final batchId in batchIds) {
      List<ReceiptJobStatus> jobs;
      try {
        jobs = await _api.listJobs(batchId);
      } catch (_) {
        continue; // transient network issue — next tick will retry
      }
      for (final job in jobs) {
        ReceiptUploadTask? entry;
        for (final t in uploaded) {
          if (t.jobId == job.id) {
            entry = t;
            break;
          }
        }
        if (entry == null) continue;
        if (job.isDone) {
          await _uploadManager.ledger.remove(entry.localId);
          anyDone = true;
        } else if (job.isFailed) {
          await _uploadManager.ledger.upsert(
            entry.copyWith(status: ReceiptUploadStatus.analysisFailed, error: job.error),
          );
        }
      }
    }
    if (anyDone && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Pending Receipts',
          style: TextStyle(
            color: Color(0xFF111827),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF111827),
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const ReceiptUploadScreen()),
          );
          if (result == true) _load();
        },
        child: const Icon(Icons.add_a_photo_outlined, color: Colors.white),
      ),
    );
  }

  Widget _buildBody() {
    return ValueListenableBuilder<List<ReceiptUploadTask>>(
      valueListenable: _uploadManager.ledger.tasks,
      builder: (context, uploadTasks, _) {
        final sorted = List.of(uploadTasks)
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        if (_loading && sorted.isEmpty && _items.isEmpty) {
          return ShimmerPlaceholder(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: 6,
              itemBuilder: (_, __) => const _PendingReceiptCardSkeleton(),
            ),
          );
        }
        if (_error != null && sorted.isEmpty && _items.isEmpty) {
          return _buildError();
        }
        if (sorted.isEmpty && _items.isEmpty) {
          return _buildEmpty();
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final task in sorted) _UploadProgressCard(task: task, manager: _uploadManager, api: _api),
              for (final item in _items)
                _PendingReceiptCard(
                  item: item,
                  onTap: () async {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReceiptUploadScreen(
                          pendingReceiptId: item.id,
                          pendingDrafts: item.transactions,
                          pendingImageUrl: item.driveUrl,
                        ),
                      ),
                    );
                    if (result == true) _load();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_outlined, size: 48, color: Color(0xFF9CA3AF)),
          const SizedBox(height: 12),
          const Text(
            'Could not load pending receipts',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _error!,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 48, color: Color(0xFF9CA3AF)),
            const SizedBox(height: 12),
            const Text(
              'No pending receipts',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Receipts you scan but don't save yet will show up here",
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadProgressCard extends StatelessWidget {
  final ReceiptUploadTask task;
  final ReceiptUploadManager manager;
  final ReceiptApi api;

  const _UploadProgressCard({required this.task, required this.manager, required this.api});

  @override
  Widget build(BuildContext context) {
    final failed = task.status == ReceiptUploadStatus.uploadFailed ||
        task.status == ReceiptUploadStatus.analysisFailed;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: failed ? Border.all(color: const Color(0xFFFCA5A5)) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 40,
              height: 40,
              child: FutureBuilder<File>(
                future: manager.fileFor(task),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return Container(color: const Color(0xFFF3F4F6));
                  return Image.file(snapshot.data!, fit: BoxFit.cover);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusLabel(task),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                if (task.status == ReceiptUploadStatus.uploading) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: task.progress > 0 ? task.progress : null,
                      minHeight: 4,
                      backgroundColor: const Color(0xFFE5E7EB),
                    ),
                  ),
                ],
                if (failed && task.error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    task.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
                  ),
                ],
              ],
            ),
          ),
          if (failed) ...[
            TextButton(
              onPressed: () => task.status == ReceiptUploadStatus.uploadFailed
                  ? manager.retryUpload(task.localId)
                  : manager.retryAnalysis(task.localId, api),
              child: const Text('Retry'),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Color(0xFF9CA3AF)),
              onPressed: () => manager.ledger.remove(task.localId),
              visualDensity: VisualDensity.compact,
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(ReceiptUploadTask task) {
    switch (task.status) {
      case ReceiptUploadStatus.queued:
        return 'Waiting to upload…';
      case ReceiptUploadStatus.uploading:
        return 'Uploading… ${(task.progress * 100).clamp(0, 100).toStringAsFixed(0)}%';
      case ReceiptUploadStatus.uploaded:
        return 'Analyzing receipt…';
      case ReceiptUploadStatus.uploadFailed:
        return 'Upload failed';
      case ReceiptUploadStatus.analysisFailed:
        return 'Analysis failed';
    }
  }
}

class _PendingReceiptCard extends StatelessWidget {
  final ReceiptListItem item;
  final VoidCallback onTap;

  const _PendingReceiptCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final txns = item.transactions;
    final merchant = txns.isNotEmpty && txns.first.merchant.isNotEmpty
        ? txns.first.merchant
        : 'Unknown merchant';
    final currency = txns.isNotEmpty ? txns.first.currency : '';
    final total = txns.fold<double>(0, (sum, t) => sum + t.amount);
    final subtitle = txns.length == 1
        ? '1 transaction · $currency ${total.toStringAsFixed(0)}'
        : '${txns.length} transactions · $currency ${total.toStringAsFixed(0)}';

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.receipt_long_outlined, color: Color(0xFFD97706), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    merchant,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}

class _PendingReceiptCardSkeleton extends StatelessWidget {
  const _PendingReceiptCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ShimmerBox(width: 40, height: 40, borderRadius: BorderRadius.circular(8)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ShimmerBox(width: 140, height: 15),
                const SizedBox(height: 6),
                const ShimmerBox(width: 90, height: 13),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const ShimmerBox(width: 18, height: 18),
        ],
      ),
    );
  }
}
