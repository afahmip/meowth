class TransactionItem {
  final int id;
  final String description;
  final double amount;
  final int quantity;
  final int? categoryId;
  final String createdAt;

  const TransactionItem({
    required this.id,
    required this.description,
    required this.amount,
    this.quantity = 1,
    this.categoryId,
    required this.createdAt,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> j) => TransactionItem(
        id: j['id'],
        description: j['description'] ?? '',
        amount: (j['amount'] as num).toDouble(),
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
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
  final String spendingType;
  final int importanceLevel;
  final int? accountId;
  final int? toAccountId;
  final String? receiptImageUrl;
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
    this.spendingType = 'one_time',
    this.importanceLevel = 3,
    this.accountId,
    this.toAccountId,
    this.receiptImageUrl,
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
        spendingType: j['spending_type'] ?? 'one_time',
        importanceLevel: (j['importance_level'] as num?)?.toInt() ?? 3,
        accountId: j['account_id'],
        toAccountId: j['to_account_id'],
        receiptImageUrl: j['receipt_image_url'],
        createdAt: j['created_at'] ?? '',
        items: (j['items'] as List? ?? [])
            .map((e) => TransactionItem.fromJson(e))
            .toList(),
      );

  String get displayName => merchant?.isNotEmpty == true ? merchant! : source;
}

class TransactionPage {
  final List<Transaction> items;
  final bool hasMore;

  const TransactionPage({required this.items, required this.hasMore});

  factory TransactionPage.fromJson(Map<String, dynamic> j) => TransactionPage(
        items: (j['items'] as List? ?? [])
            .map((e) => Transaction.fromJson(e))
            .toList(),
        hasMore: j['has_more'] ?? false,
      );
}

class TransactionItemInput {
  final String description;
  final double amount;
  final int quantity;
  final int? categoryId;

  const TransactionItemInput({
    required this.description,
    required this.amount,
    this.quantity = 1,
    this.categoryId,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'amount': amount,
        'quantity': quantity,
        if (categoryId != null) 'category_id': categoryId,
      };
}

class TransactionInput {
  final String? merchant;
  final double amount;
  final String currency;
  final String? transactionDate;
  final String type;
  final String spendingType;
  final int importanceLevel;
  final String source;
  final int? categoryId;
  final List<TransactionItemInput> items;

  const TransactionInput({
    this.merchant,
    required this.amount,
    required this.currency,
    this.transactionDate,
    required this.type,
    this.spendingType = 'one_time',
    this.importanceLevel = 3,
    this.source = 'manual',
    this.categoryId,
    this.items = const [],
  });

  Map<String, dynamic> toJson() => {
        if (merchant != null && merchant!.isNotEmpty) 'merchant': merchant,
        'amount': amount,
        'currency': currency,
        if (transactionDate != null) 'transaction_date': transactionDate,
        'type': type,
        'spending_type': spendingType,
        'importance_level': importanceLevel,
        'source': source,
        if (categoryId != null) 'category_id': categoryId,
        if (items.isNotEmpty) 'items': items.map((e) => e.toJson()).toList(),
      };
}
