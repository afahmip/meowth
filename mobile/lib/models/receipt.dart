class ReceiptItemDraft {
  final String description;
  final double amount;
  final int quantity;
  final String? category;
  final int? categoryId;

  const ReceiptItemDraft({
    required this.description,
    required this.amount,
    this.quantity = 1,
    this.category,
    this.categoryId,
  });

  factory ReceiptItemDraft.fromJson(Map<String, dynamic> j) => ReceiptItemDraft(
        description: j['description'] ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        category: j['category'],
      );
}

class ReceiptTransactionDraft {
  final String merchant;
  final double amount;
  final String currency;
  final String? transactionDate;
  final String type;
  final String? notes;
  final String? category;
  final int? categoryId;
  final List<ReceiptItemDraft> items;

  const ReceiptTransactionDraft({
    required this.merchant,
    required this.amount,
    required this.currency,
    this.transactionDate,
    required this.type,
    this.notes,
    this.category,
    this.categoryId,
    this.items = const [],
  });

  factory ReceiptTransactionDraft.fromJson(Map<String, dynamic> j) =>
      ReceiptTransactionDraft(
        merchant: j['merchant'] ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        currency: j['currency'] ?? 'USD',
        transactionDate: j['transaction_date'],
        type: j['type'] ?? 'expense',
        notes: j['notes'],
        category: j['category'],
        items: (j['items'] as List? ?? [])
            .map((e) => ReceiptItemDraft.fromJson(e))
            .toList(),
      );
}

class ReceiptAnalysis {
  final int id;
  final List<ReceiptTransactionDraft> transactions;

  const ReceiptAnalysis({required this.id, required this.transactions});

  factory ReceiptAnalysis.fromJson(Map<String, dynamic> j) => ReceiptAnalysis(
        id: j['id'],
        transactions: (j['transactions'] as List? ?? [])
            .map((e) => ReceiptTransactionDraft.fromJson(e))
            .toList(),
      );
}
