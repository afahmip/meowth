import 'package:flutter/material.dart';
import '../api/transaction_api.dart';
import '../config.dart';
import '../models/transaction.dart';
import '../widgets/transaction_card.dart';
import 'summary_screen.dart';
import 'transaction_detail_screen.dart';
import 'transaction_form_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TransactionApi _api;
  List<Transaction> _transactions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = TransactionApi(AppConfig.baseUrl);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final txns = await _api.list();
      setState(() => _transactions = txns);
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
          'Transactions',
          style: TextStyle(
            color: Color(0xFF111827),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.donut_large_outlined, color: Color(0xFF111827)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SummaryScreen()),
              );
            },
          ),
          if (AppConfig.env == Env.local)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'LOCAL',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFD97706),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => TransactionFormScreen(api: _api),
            ),
          );
          if (result == true) _load();
        },
        backgroundColor: const Color(0xFF111827),
        child: const Icon(Icons.add, color: Colors.white),
      ),
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
            const Icon(Icons.wifi_off_outlined,
                size: 48, color: Color(0xFF9CA3AF)),
            const SizedBox(height: 12),
            Text(
              'Could not load transactions',
              style: const TextStyle(
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
    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.receipt_long_outlined,
                size: 48, color: Color(0xFF9CA3AF)),
            const SizedBox(height: 12),
            const Text(
              'No transactions yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap + to add your first transaction',
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _transactions.length,
        itemBuilder: (_, i) => TransactionCard(
          transaction: _transactions[i],
          onTap: () async {
            final result = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (_) => TransactionDetailScreen(
                  transaction: _transactions[i],
                  api: _api,
                ),
              ),
            );
            if (result != null) _load();
          },
        ),
      ),
    );
  }
}
