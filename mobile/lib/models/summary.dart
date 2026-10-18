// One currency's share of a blended total — a category or period isn't
// necessarily all in one currency, so this is what lets the UI show real
// amounts instead of a meaningless sum across currencies.
class CurrencyAmount {
  final String currency;
  final double total;

  const CurrencyAmount({required this.currency, required this.total});

  factory CurrencyAmount.fromJson(Map<String, dynamic> j) => CurrencyAmount(
        currency: j['currency'] ?? '',
        total: (j['total'] as num).toDouble(),
      );
}

class CategorySummary {
  final int? categoryId;
  final String categoryName;
  final String categoryEmoji;
  final double total;
  final double percentage;
  final List<CurrencyAmount> amounts;

  const CategorySummary({
    this.categoryId,
    required this.categoryName,
    this.categoryEmoji = '',
    required this.total,
    required this.percentage,
    this.amounts = const [],
  });

  factory CategorySummary.fromJson(Map<String, dynamic> j) => CategorySummary(
        categoryId: j['category_id'],
        categoryName: j['category_name'] ?? 'Uncategorized',
        categoryEmoji: j['category_emoji'] ?? '',
        total: (j['total'] as num).toDouble(),
        percentage: (j['percentage'] as num).toDouble(),
        amounts: (j['amounts'] as List? ?? [])
            .map((e) => CurrencyAmount.fromJson(e))
            .toList(),
      );

  String get label => categoryEmoji.isNotEmpty ? '$categoryEmoji $categoryName' : categoryName;
}

class TransactionSummary {
  final String from;
  final String to;
  final String mode;
  final double total;
  final List<CurrencyAmount> totals;
  final List<CategorySummary> categories;

  const TransactionSummary({
    required this.from,
    required this.to,
    required this.mode,
    required this.total,
    required this.totals,
    required this.categories,
  });

  factory TransactionSummary.fromJson(Map<String, dynamic> j) =>
      TransactionSummary(
        from: j['from'] ?? '',
        to: j['to'] ?? '',
        mode: j['mode'] ?? 'transactions',
        total: (j['total'] as num).toDouble(),
        totals: (j['totals'] as List? ?? [])
            .map((e) => CurrencyAmount.fromJson(e))
            .toList(),
        categories: (j['categories'] as List? ?? [])
            .map((e) => CategorySummary.fromJson(e))
            .toList(),
      );
}
