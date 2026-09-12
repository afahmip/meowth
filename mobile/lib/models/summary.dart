class CategorySummary {
  final int? categoryId;
  final String categoryName;
  final String categoryEmoji;
  final double total;
  final double percentage;

  const CategorySummary({
    this.categoryId,
    required this.categoryName,
    this.categoryEmoji = '',
    required this.total,
    required this.percentage,
  });

  factory CategorySummary.fromJson(Map<String, dynamic> j) => CategorySummary(
        categoryId: j['category_id'],
        categoryName: j['category_name'] ?? 'Uncategorized',
        categoryEmoji: j['category_emoji'] ?? '',
        total: (j['total'] as num).toDouble(),
        percentage: (j['percentage'] as num).toDouble(),
      );

  String get label => categoryEmoji.isNotEmpty ? '$categoryEmoji $categoryName' : categoryName;
}

class TransactionSummary {
  final String from;
  final String to;
  final String mode;
  final double total;
  final List<CategorySummary> categories;

  const TransactionSummary({
    required this.from,
    required this.to,
    required this.mode,
    required this.total,
    required this.categories,
  });

  factory TransactionSummary.fromJson(Map<String, dynamic> j) =>
      TransactionSummary(
        from: j['from'] ?? '',
        to: j['to'] ?? '',
        mode: j['mode'] ?? 'transactions',
        total: (j['total'] as num).toDouble(),
        categories: (j['categories'] as List? ?? [])
            .map((e) => CategorySummary.fromJson(e))
            .toList(),
      );
}
