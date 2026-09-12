import 'package:flutter/material.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../utils/drive_image.dart';
import 'shimmer_placeholder.dart';

class TransactionCard extends StatelessWidget {
  final Transaction transaction;
  final Map<int, Category> categoriesById;
  final VoidCallback onTap;

  const TransactionCard({
    super.key,
    required this.transaction,
    required this.categoriesById,
    required this.onTap,
  });

  Color get _amountColor => transaction.type == 'income'
      ? const Color(0xFF16A34A)
      : transaction.type == 'expense'
          ? const Color(0xFFDC2626)
          : const Color(0xFF2563EB);

  // Transaction-level category first, then item categories in order, deduped
  // by id, capped at 3 — this is what gets shown as overlapping badges.
  List<String> _topCategoryEmojis() {
    final seen = <int>{};
    final emojis = <String>[];
    void tryAdd(int? categoryId) {
      if (categoryId == null || emojis.length >= 3 || seen.contains(categoryId)) return;
      seen.add(categoryId);
      final emoji = categoriesById[categoryId]?.emoji;
      if (emoji != null && emoji.isNotEmpty) emojis.add(emoji);
    }

    tryAdd(transaction.categoryId);
    for (final item in transaction.items) {
      tryAdd(item.categoryId);
    }
    return emojis;
  }

  @override
  Widget build(BuildContext context) {
    final isExpense = transaction.type == 'expense';
    final isIncome = transaction.type == 'income';
    final sign = isIncome ? '+' : isExpense ? '-' : '↔';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            _buildLeading(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.displayName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF111827),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (transaction.transactionDate != null || transaction.spendingType == 'living_cost') ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (transaction.transactionDate != null)
                          Text(
                            transaction.transactionDate!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        if (transaction.spendingType == 'living_cost') ...[
                          if (transaction.transactionDate != null) const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Living Cost',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Text(
              '$sign ${transaction.currency} ${_formatAmount(transaction.amount)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The avatar section: a receipt thumbnail (falling back to a plain
  // direction icon when there's no image) with up to 3 category emoji
  // badges overlapping its bottom-right corner like a stack of avatars.
  Widget _buildLeading() {
    final emojis = _topCategoryEmojis();
    final imageSrc =
        transaction.receiptImageUrl != null ? driveImageSrc(transaction.receiptImageUrl!) : null;

    final base = imageSrc != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              imageSrc,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallbackIcon(),
            ),
          )
        : _fallbackIcon();

    if (emojis.isEmpty) {
      return SizedBox(width: 40, height: 40, child: base);
    }

    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(top: 0, left: 0, child: base),
          Positioned(
            bottom: -6,
            right: -6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < emojis.length; i++)
                  Container(
                    margin: EdgeInsets.only(left: i == 0 ? 0 : -8),
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(emojis[i], style: const TextStyle(fontSize: 10)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackIcon() {
    final isIncome = transaction.type == 'income';
    final isExpense = transaction.type == 'expense';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _amountColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        isIncome
            ? Icons.arrow_downward_rounded
            : isExpense
                ? Icons.arrow_upward_rounded
                : Icons.swap_horiz_rounded,
        color: _amountColor,
        size: 20,
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}K';
    }
    return amount.toStringAsFixed(0);
  }
}

/// Placeholder shaped like [TransactionCard], shown while the real list is
/// still loading. Meant to sit inside a [ShimmerPlaceholder].
class TransactionCardSkeleton extends StatelessWidget {
  const TransactionCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                const ShimmerBox(width: 120, height: 14),
                const SizedBox(height: 8),
                const ShimmerBox(width: 70, height: 11),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const ShimmerBox(width: 56, height: 14),
        ],
      ),
    );
  }
}
