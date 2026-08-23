import 'package:flutter/material.dart';
import '../api/transaction_api.dart';
import '../config.dart';
import '../models/summary.dart';
import '../models/transaction.dart';
import '../widgets/storage_percentage_bar.dart';
import '../widgets/transaction_card.dart';
import 'transaction_detail_screen.dart';

const _palette = [
  Color(0xFF2563EB),
  Color(0xFFDC2626),
  Color(0xFF16A34A),
  Color(0xFFD97706),
  Color(0xFF7C3AED),
  Color(0xFFDB2777),
  Color(0xFF0891B2),
  Color(0xFF65A30D),
];

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  late final TransactionApi _api;

  DateTime? _from;
  DateTime? _to;
  TransactionSummary? _summary;
  List<Transaction> _transactions = [];
  String? _selectedCategoryKey;
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = TransactionApi(AppConfig.baseUrl);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _categoryKey(int? categoryId) => categoryId?.toString() ?? 'none';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _api.summary(
        from: _from == null ? null : _fmt(_from!),
        to: _to == null ? null : _fmt(_to!),
      );
      final txns = await _api.list(from: summary.from, to: summary.to);
      setState(() {
        _summary = summary;
        _from = DateTime.parse(summary.from);
        _to = DateTime.parse(summary.to);
        _transactions = txns;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final initial = (isFrom ? _from : _to) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
      _selectedCategoryKey = null;
    });
    _load();
  }

  List<Transaction> get _filteredTransactions {
    final kw = _searchController.text.trim().toLowerCase();
    return _transactions.where((t) {
      if (_selectedCategoryKey != null &&
          _categoryKey(t.categoryId) != _selectedCategoryKey) {
        return false;
      }
      if (kw.isNotEmpty &&
          !'${t.displayName} ${t.source}'.toLowerCase().contains(kw)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Summary',
          style: TextStyle(
            color: Color(0xFF111827),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _summary == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _summary == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_outlined,
                size: 48, color: Color(0xFF9CA3AF)),
            const SizedBox(height: 12),
            Text(
              'Could not load summary',
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

    final summary = _summary!;
    final colors = List.generate(
      summary.categories.length,
      (i) => _palette[i % _palette.length],
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: _dateChip('From', _from, () => _pickDate(true))),
                const SizedBox(width: 8),
                Expanded(child: _dateChip('To', _to, () => _pickDate(false))),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${summary.categories.isEmpty ? 0 : summary.total.toStringAsFixed(0)} spent',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                StoragePercentageBar(
                  categories: summary.categories,
                  colors: colors,
                  selectedCategoryKey: _selectedCategoryKey,
                ),
                const SizedBox(height: 14),
                if (summary.categories.isEmpty)
                  const Text(
                    'No expenses in this period',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < summary.categories.length; i++)
                        _categoryTag(summary.categories[i], colors[i]),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search transactions',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildTransactionList(),
        ],
      ),
    );
  }

  Widget _dateChip(String label, DateTime? date, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 2),
            Text(
              date == null ? '-' : _fmt(date),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryTag(CategorySummary c, Color color) {
    final key = _categoryKey(c.categoryId);
    final selected = _selectedCategoryKey == key;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedCategoryKey = selected ? null : key;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '${c.categoryName} ${c.percentage.toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList() {
    final txns = _filteredTransactions;
    if (txns.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'No matching transactions',
            style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final t in txns)
          TransactionCard(
            transaction: t,
            onTap: () async {
              final result = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      TransactionDetailScreen(transaction: t, api: _api),
                ),
              );
              if (result != null) _load();
            },
          ),
      ],
    );
  }
}
