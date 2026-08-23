class ReceiptItemDraft {
  final String description;
  final double amount;

  const ReceiptItemDraft({required this.description, required this.amount});

  factory ReceiptItemDraft.fromJson(Map<String, dynamic> j) => ReceiptItemDraft(
        description: j['description'] ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
      );
}

class ReceiptTransactionDraft {
  final String merchant;
  final double amount;
  final String currency;
  final String? transactionDate;
  final String type;
  final String? notes;
  final List<ReceiptItemDraft> items;

  const ReceiptTransactionDraft({
    required this.merchant,
    required this.amount,
    required this.currency,
    this.transactionDate,
    required this.type,
    this.notes,
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
