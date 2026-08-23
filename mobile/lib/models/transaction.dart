class TransactionItem {
  final int id;
  final String description;
  final double amount;
  final int? categoryId;
  final String createdAt;

  const TransactionItem({
    required this.id,
    required this.description,
    required this.amount,
    this.categoryId,
    required this.createdAt,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> j) => TransactionItem(
        id: j['id'],
        description: j['description'] ?? '',
        amount: (j['amount'] as num).toDouble(),
        categoryId: j['category_id'],
        createdAt: j['created_at'] ?? '',
      );
}

class Transaction {
  final int id;
  final String source;
  final String? merchant;
  final double amount;
  final String currency;
  final String? transactionDate;
  final int? categoryId;
  final String type;
  final int? accountId;
  final int? toAccountId;
  final String createdAt;
  final List<TransactionItem> items;

  const Transaction({
    required this.id,
    required this.source,
    this.merchant,
    required this.amount,
    required this.currency,
    this.transactionDate,
    this.categoryId,
    required this.type,
    this.accountId,
    this.toAccountId,
    required this.createdAt,
    required this.items,
  });

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id'],
        source: j['source'] ?? '',
        merchant: j['merchant'],
        amount: (j['amount'] as num).toDouble(),
        currency: j['currency'] ?? 'IDR',
        transactionDate: j['transaction_date'],
        categoryId: j['category_id'],
        type: j['type'] ?? 'expense',
        accountId: j['account_id'],
        toAccountId: j['to_account_id'],
        createdAt: j['created_at'] ?? '',
        items: (j['items'] as List? ?? [])
            .map((e) => TransactionItem.fromJson(e))
            .toList(),
      );

  String get displayName => merchant?.isNotEmpty == true ? merchant! : source;
}

class TransactionItemInput {
  final String description;
  final double amount;

  const TransactionItemInput({required this.description, required this.amount});

  Map<String, dynamic> toJson() => {'description': description, 'amount': amount};
}

class TransactionInput {
  final String? merchant;
  final double amount;
  final String currency;
  final String? transactionDate;
  final String type;
  final String source;
  final List<TransactionItemInput> items;

  const TransactionInput({
    this.merchant,
    required this.amount,
    required this.currency,
    this.transactionDate,
    required this.type,
    this.source = 'manual',
    this.items = const [],
  });

  Map<String, dynamic> toJson() => {
        if (merchant != null && merchant!.isNotEmpty) 'merchant': merchant,
        'amount': amount,
        'currency': currency,
        if (transactionDate != null) 'transaction_date': transactionDate,
        'type': type,
        'source': source,
        if (items.isNotEmpty) 'items': items.map((e) => e.toJson()).toList(),
      };
}
