import 'package:flutter/material.dart';
import '../api/receipt_api.dart';
import '../config.dart';
import '../models/receipt.dart';
import 'receipt_upload_screen.dart';

class PendingReceiptsScreen extends StatefulWidget {
  const PendingReceiptsScreen({super.key});

  @override
  State<PendingReceiptsScreen> createState() => _PendingReceiptsScreenState();
}

class _PendingReceiptsScreenState extends State<PendingReceiptsScreen> {
  late final ReceiptApi _api;
  List<ReceiptListItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = ReceiptApi(AppConfig.baseUrl);
    _load();
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
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
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
    if (_items.isEmpty) {
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length,
        itemBuilder: (_, i) => _PendingReceiptCard(
          item: _items[i],
          onTap: () async {
            final result = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => ReceiptUploadScreen(
                  pendingReceiptId: _items[i].id,
                  pendingDrafts: _items[i].transactions,
                  pendingImageUrl: _items[i].driveUrl,
                ),
              ),
            );
            if (result == true) _load();
          },
        ),
      ),
    );
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
