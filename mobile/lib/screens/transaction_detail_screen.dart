import 'package:flutter/material.dart';
import '../api/category_api.dart';
import '../api/transaction_api.dart';
import '../config.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../utils/drive_image.dart';
import 'transaction_form_screen.dart';

class TransactionDetailScreen extends StatefulWidget {
  final Transaction transaction;
  final TransactionApi api;

  const TransactionDetailScreen({
    super.key,
    required this.transaction,
    required this.api,
  });

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  late final CategoryApi _categoryApi;
  late List<TransactionItem> _items;
  List<Category> _categories = [];

  @override
  void initState() {
    super.initState();
    _categoryApi = CategoryApi(AppConfig.baseUrl);
    _items = List.of(widget.transaction.items);
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await _categoryApi.list();
      if (mounted) setState(() => _categories = cats);
    } catch (_) {
      // Item category editing just stays unavailable if this fails.
    }
  }

  Map<int, Category> get _categoriesById => {for (final c in _categories) c.id: c};

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text('Are you sure you want to delete this transaction?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.api.delete(widget.transaction.id);
    if (context.mounted) Navigator.pop(context, 'deleted');
  }

  Future<void> _editItemCategory(TransactionItem item) async {
    if (_categories.isEmpty) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Item Category',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            for (final c in _categories)
              ListTile(
                leading: Text(
                  c.emoji.isNotEmpty ? c.emoji : '🏷️',
                  style: const TextStyle(fontSize: 20),
                ),
                title: Text(c.name),
                trailing: item.categoryId == c.id
                    ? const Icon(Icons.check, color: Color(0xFF111827))
                    : null,
                onTap: () => Navigator.pop(ctx, c.id),
              ),
          ],
        ),
      ),
    );
    if (selected == null || selected == item.categoryId) return;

    final index = _items.indexWhere((i) => i.id == item.id);
    final previous = _items[index];
    setState(() {
      _items[index] = TransactionItem(
        id: item.id,
        description: item.description,
        amount: item.amount,
        quantity: item.quantity,
        categoryId: selected,
        createdAt: item.createdAt,
      );
    });
    try {
      await widget.api.updateItem(
        widget.transaction.id,
        item.id,
        TransactionItemInput(
          description: item.description,
          amount: item.amount,
          quantity: item.quantity,
          categoryId: selected,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _items[index] = previous);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final transaction = widget.transaction;
    final isIncome = transaction.type == 'income';
    final isExpense = transaction.type == 'expense';
    final amountColor = isIncome
        ? const Color(0xFF16A34A)
        : isExpense
            ? const Color(0xFFDC2626)
            : const Color(0xFF2563EB);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Transaction',
          style: TextStyle(
            color: Color(0xFF111827),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => TransactionFormScreen(
                    api: widget.api,
                    transaction: transaction,
                  ),
                ),
              );
              if (result == true && context.mounted) {
                Navigator.pop(context, 'updated');
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
            onPressed: () => _delete(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  transaction.displayName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '${isIncome ? '+' : isExpense ? '-' : '↔'} ${transaction.currency} ${_formatAmount(transaction.amount)}',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: amountColor,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: amountColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    transaction.type[0].toUpperCase() +
                        transaction.type.substring(1),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: amountColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (transaction.receiptImageUrl != null) ...[
            const SizedBox(height: 12),
            _buildReceiptImage(context, transaction.receiptImageUrl!),
          ],
          const SizedBox(height: 12),
          _infoCard([
            if (transaction.transactionDate != null)
              _row('Date', transaction.transactionDate!),
            _row('Source', transaction.source),
            _row('Currency', transaction.currency),
            _row('Spending Type', transaction.spendingType == 'living_cost'
                ? 'Living Cost'
                : 'One-time'),
            _row('Importance', '${transaction.importanceLevel}/5'),
          ]),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionTitle('Items'),
            const SizedBox(height: 8),
            _infoCard(_items.map((item) => _itemRow(transaction, item)).toList()),
          ],
        ],
      ),
    );
  }

  Widget _buildReceiptImage(BuildContext context, String driveUrl) {
    final src = driveImageSrc(driveUrl);
    if (src == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: InteractiveViewer(
            child: Image.network(src, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          src,
          height: 160,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _infoCard(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: rows),
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B7280),
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF111827),
              ),
            ),
          ],
        ),
      );

  Widget _itemRow(Transaction transaction, TransactionItem item) {
    final category = item.categoryId != null ? _categoriesById[item.categoryId] : null;
    return InkWell(
      onTap: _categories.isEmpty ? null : () => _editItemCategory(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.quantity > 1
                        ? '${item.description} ×${item.quantity}'
                        : item.description,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        category != null ? category.label : 'Uncategorized',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: category != null
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF9CA3AF),
                        ),
                      ),
                      if (_categories.isNotEmpty) ...[
                        const SizedBox(width: 2),
                        const Icon(Icons.expand_more, size: 14, color: Color(0xFF9CA3AF)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${transaction.currency} ${_formatAmount(item.amount)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF111827),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(2)}M';
    }
    return amount.toStringAsFixed(0);
  }
}
