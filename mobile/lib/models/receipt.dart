class ReceiptItemDraft {
  final String description;
  final double amount;
  final int quantity;
  final int? categoryId;

  const ReceiptItemDraft({
    required this.description,
    required this.amount,
    this.quantity = 1,
    this.categoryId,
  });

  factory ReceiptItemDraft.fromJson(Map<String, dynamic> j) => ReceiptItemDraft(
        description: j['description'] ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        categoryId: j['category_id'],
      );
}

class ReceiptTransactionDraft {
  final String merchant;
  final double amount;
  final String currency;
  final String? transactionDate;
  final String type;
  final String? notes;
  final int? categoryId;
  final String spendingType;
  final int importanceLevel;
  final List<ReceiptItemDraft> items;

  const ReceiptTransactionDraft({
    required this.merchant,
    required this.amount,
    required this.currency,
    this.transactionDate,
    required this.type,
    this.notes,
    this.categoryId,
    this.spendingType = 'one_time',
    this.importanceLevel = 3,
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
        categoryId: j['category_id'],
        spendingType: j['spending_type'] ?? 'one_time',
        importanceLevel: (j['importance_level'] as num?)?.toInt() ?? 3,
        items: (j['items'] as List? ?? [])
            .map((e) => ReceiptItemDraft.fromJson(e))
            .toList(),
      );
}

// One entry from GET /receipts/jobs?batch_id=... — the async upload+analyze
// job behind a single uploaded image (see ReceiptUploadManager). Once
// status is "done", the resulting receipt already shows up via the regular
// GET /receipts list, so this type only carries what's needed to track
// in-flight progress and surface a failure.
class ReceiptJobStatus {
  final int id;
  final String status; // queued | processing | done | failed
  final String? error;
  final int? analyzedReceiptImageId;

  const ReceiptJobStatus({
    required this.id,
    required this.status,
    this.error,
    this.analyzedReceiptImageId,
  });

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';

  factory ReceiptJobStatus.fromJson(Map<String, dynamic> j) => ReceiptJobStatus(
        id: j['id'],
        status: j['status'] ?? 'queued',
        error: j['error'],
        analyzedReceiptImageId: j['analyzed_receipt_image_id'],
      );
}

// A previously-analyzed receipt as returned by GET /receipts. transactionId
// is null until the drafts are reviewed and saved, which is what makes a
// receipt show up as "pending" / not-yet-saved.
class ReceiptListItem {
  final int id;
  final String filename;
  final String? driveUrl;
  final int? transactionId;
  final List<ReceiptTransactionDraft> transactions;
  final String createdAt;

  const ReceiptListItem({
    required this.id,
    required this.filename,
    this.driveUrl,
    this.transactionId,
    this.transactions = const [],
    required this.createdAt,
  });

  bool get isSaved => transactionId != null;

  factory ReceiptListItem.fromJson(Map<String, dynamic> j) => ReceiptListItem(
        id: j['id'],
        filename: j['filename'] ?? '',
        driveUrl: j['drive_url'],
        transactionId: j['transaction_id'],
        transactions: (j['transactions'] as List? ?? [])
            .map((e) => ReceiptTransactionDraft.fromJson(e))
            .toList(),
        createdAt: j['created_at'] ?? '',
      );
}
