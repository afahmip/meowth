import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../api/category_api.dart';
import '../api/receipt_api.dart';
import '../api/transaction_api.dart';
import '../config.dart';
import '../models/category.dart';
import '../models/receipt.dart';
import '../models/transaction.dart';

enum _Stage { picking, analyzing, reviewing }

const _currencies = ['AED', 'IDR', 'SGD', 'THB', 'USD'];

String _normalizeCurrency(String currency) {
  final upper = currency.toUpperCase();
  return _currencies.contains(upper) ? upper : 'AED';
}

class ReceiptUploadScreen extends StatefulWidget {
  // When resuming a previously-analyzed receipt that hasn't been saved yet
  // (see PendingReceiptsScreen), these skip straight to the review stage
  // instead of showing the image picker.
  final int? pendingReceiptId;
  final List<ReceiptTransactionDraft>? pendingDrafts;
  final String? pendingImageUrl;

  const ReceiptUploadScreen({
    super.key,
    this.pendingReceiptId,
    this.pendingDrafts,
    this.pendingImageUrl,
  });

  @override
  State<ReceiptUploadScreen> createState() => _ReceiptUploadScreenState();
}

class _ReceiptUploadScreenState extends State<ReceiptUploadScreen> {
  late final ReceiptApi _receiptApi;
  late final TransactionApi _txnApi;
  late final CategoryApi _categoryApi;
  // Kicked off at screen init so it's typically already resolved by the time
  // analysis finishes; awaited (with failures swallowed) right before
  // building the review UI so every draft card's category resolution has
  // the real list instead of racing an empty one.
  late final Future<List<Category>> _categoriesFuture;
  final _picker = ImagePicker();

  _Stage _stage = _Stage.picking;
  String? _error;
  int? _receiptId;
  File? _pickedImage;
  List<ReceiptTransactionDraft> _drafts = [];
  // Stable per-draft identity, kept in lockstep with _drafts. Using the list
  // index as a Key would make a card removal shift every later card's index,
  // causing Flutter to reuse the wrong card's editing state after the shift.
  List<Key> _draftKeys = [];
  List<Category> _categories = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _receiptApi = ReceiptApi(AppConfig.baseUrl);
    _txnApi = TransactionApi(AppConfig.baseUrl);
    _categoryApi = CategoryApi(AppConfig.baseUrl);
    _categoriesFuture = _categoryApi.list().catchError((_) => <Category>[]);
    if (widget.pendingReceiptId != null) {
      _stage = _Stage.analyzing;
      _loadPending();
    }
  }

  Future<void> _loadPending() async {
    final cats = await _categoriesFuture;
    setState(() {
      _receiptId = widget.pendingReceiptId;
      _categories = cats;
      _drafts = List.of(widget.pendingDrafts ?? []);
      _draftKeys = List.generate(_drafts.length, (_) => UniqueKey());
      _stage = _Stage.reviewing;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    final file = File(picked.path);

    setState(() {
      _stage = _Stage.analyzing;
      _error = null;
      _pickedImage = file;
    });
    try {
      final result = await _receiptApi.analyze(file);
      final cats = await _categoriesFuture;
      setState(() {
        _receiptId = result.id;
        _categories = cats;
        _drafts = result.transactions;
        _draftKeys = List.generate(_drafts.length, (_) => UniqueKey());
        if (result.transactions.isEmpty) {
          _stage = _Stage.picking;
          _error = 'No transactions were found in that image.';
        } else {
          _stage = _Stage.reviewing;
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _stage = _Stage.picking;
      });
    }
  }

  void _removeDraft(int index) {
    setState(() {
      _drafts.removeAt(index);
      _draftKeys.removeAt(index);
    });
  }

  void _addDraft() {
    setState(() {
      _drafts.add(const ReceiptTransactionDraft(
        merchant: '',
        amount: 0,
        currency: 'AED',
        type: 'expense',
      ));
      _draftKeys.add(UniqueKey());
    });
  }

  Future<void> _saveAll() async {
    if (_drafts.isEmpty) return;
    setState(() => _saving = true);
    int? firstCreatedId;
    try {
      // Drop each draft from the list as soon as it's saved, so a retry
      // after a failure only resubmits what's left instead of duplicating
      // transactions that were already created.
      while (_drafts.isNotEmpty) {
        final d = _drafts.first;
        final id = await _txnApi.create(TransactionInput(
          merchant: d.merchant,
          amount: d.amount,
          currency: d.currency,
          transactionDate: d.transactionDate,
          type: d.type,
          source: 'receipt',
          categoryId: d.categoryId,
          items: d.items
              .map((i) => TransactionItemInput(
                    description: i.description,
                    amount: i.amount,
                    quantity: i.quantity,
                    categoryId: i.categoryId,
                  ))
              .toList(),
        ));
        firstCreatedId ??= id;
        setState(() {
          _drafts.removeAt(0);
          _draftKeys.removeAt(0);
        });
      }
      if (_receiptId != null && firstCreatedId != null) {
        try {
          await _receiptApi.assignTransaction(_receiptId!, firstCreatedId);
        } catch (_) {
          // Best-effort: the transactions are already saved, so don't block
          // on failing to link them back to the receipt image.
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.pendingReceiptId != null ? 'Review Receipt' : 'Scan Receipt',
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),
      body: switch (_stage) {
        _Stage.picking => _buildPicker(),
        _Stage.analyzing => const Center(child: CircularProgressIndicator()),
        _Stage.reviewing => _buildReview(),
      },
    );
  }

  Widget _buildPicker() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined,
                size: 56, color: Color(0xFF9CA3AF)),
            const SizedBox(height: 16),
            const Text(
              'Upload a receipt to auto-fill transactions',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Color(0xFF374151)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFFDC2626)),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take Photo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  foregroundColor: Colors.white,
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose from Gallery'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF111827),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReview() {
    return Column(
      children: [
        if (_pickedImage != null)
          _buildImagePreview()
        else if (widget.pendingImageUrl != null)
          _buildNetworkImagePreview(widget.pendingImageUrl!),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addDraft,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Transaction'),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: _drafts.length,
            itemBuilder: (_, i) => _DraftTransactionCard(
              key: _draftKeys[i],
              draft: _drafts[i],
              categories: _categories,
              onChanged: (updated) => _drafts[i] = updated,
              onRemove: () => _removeDraft(i),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Discard All'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _saving || _drafts.isEmpty ? null : _saveAll,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF111827),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text('Save All (${_drafts.length})'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    final image = _pickedImage!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: const EdgeInsets.all(12),
            child: InteractiveViewer(child: Image.file(image)),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            image,
            height: 160,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  // Drive "view" links render an HTML viewer, not a raw image, so the file
  // id is pulled out and pointed at googleusercontent instead, which serves
  // the image directly for publicly-shared files.
  String? _driveImageSrc(String driveUrl) {
    final id = RegExp(r'/d/([^/]+)/').firstMatch(driveUrl)?.group(1);
    return id == null ? null : 'https://lh3.googleusercontent.com/d/$id';
  }

  Widget _buildNetworkImagePreview(String driveUrl) {
    final src = _driveImageSrc(driveUrl);
    if (src == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
}

class _DraftTransactionCard extends StatefulWidget {
  final ReceiptTransactionDraft draft;
  final List<Category> categories;
  final ValueChanged<ReceiptTransactionDraft> onChanged;
  final VoidCallback onRemove;

  const _DraftTransactionCard({
    super.key,
    required this.draft,
    required this.categories,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_DraftTransactionCard> createState() => _DraftTransactionCardState();
}

class _DraftTransactionCardState extends State<_DraftTransactionCard> {
  late final TextEditingController _merchantCtrl;
  late final TextEditingController _amountCtrl;
  late String _currency;
  late String _type;
  late int? _categoryId;
  DateTime? _date;
  late List<ReceiptItemDraft> _items;
  // Stable per-item identity, kept in lockstep with _items — same reasoning
  // as _draftKeys in the parent screen: index-based keys reuse the wrong
  // row's controllers after a removal shifts later items down.
  late List<Key> _itemKeys;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _merchantCtrl = TextEditingController(text: d.merchant);
    _amountCtrl = TextEditingController(text: d.amount.toStringAsFixed(2));
    _currency = _normalizeCurrency(d.currency);
    _type = d.type;
    _categoryId = d.categoryId;
    _date =
        d.transactionDate != null ? DateTime.tryParse(d.transactionDate!) : null;
    _items = List.of(d.items);
    _itemKeys = List.generate(_items.length, (_) => UniqueKey());
    if (_currency != d.currency) _emit();
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(ReceiptTransactionDraft(
      merchant: _merchantCtrl.text.trim(),
      amount: double.tryParse(_amountCtrl.text.trim()) ?? widget.draft.amount,
      currency: _currency,
      transactionDate: _date?.toIso8601String().substring(0, 10),
      type: _type,
      notes: widget.draft.notes,
      categoryId: _categoryId,
      items: _items,
    ));
  }

  void _addItem() {
    setState(() {
      _items.add(const ReceiptItemDraft(description: '', amount: 0));
      _itemKeys.add(UniqueKey());
    });
    _emit();
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _itemKeys.removeAt(index);
    });
    _emit();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _emit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _merchantCtrl,
                  onChanged: (_) => _emit(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Merchant',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Color(0xFF9CA3AF)),
                onPressed: widget.onRemove,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _amountCtrl,
                  onChanged: (_) => _emit(),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _fieldDecoration('Amount'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _currency,
                  isExpanded: true,
                  items: [
                    for (final c in _currencies)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _currency = v);
                    _emit();
                  },
                  decoration: _fieldDecoration('Currency'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _date != null
                          ? _date!.toIso8601String().substring(0, 10)
                          : 'Select date',
                      style: TextStyle(
                        fontSize: 13,
                        color: _date != null
                            ? const Color(0xFF111827)
                            : const Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              for (final type in ['expense', 'income'])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ChoiceChip(
                    label: Text(type),
                    selected: _type == type,
                    onSelected: (_) {
                      setState(() => _type = type);
                      _emit();
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            value: _categoryId,
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: null, child: Text('Uncategorized')),
              for (final c in widget.categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) {
              setState(() => _categoryId = v);
              _emit();
            },
            decoration: _fieldDecoration('Category'),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 4),
          for (var i = 0; i < _items.length; i++)
            _ItemRow(
              key: _itemKeys[i],
              item: _items[i],
              categories: widget.categories,
              onChanged: (updated) => _items[i] = updated,
              onRemove: () => _removeItem(i),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: TextButton.icon(
              onPressed: _addItem,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                foregroundColor: const Color(0xFF6B7280),
              ),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add Item', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF111827)),
        ),
      );
}

class _ItemRow extends StatefulWidget {
  final ReceiptItemDraft item;
  final List<Category> categories;
  final ValueChanged<ReceiptItemDraft> onChanged;
  final VoidCallback onRemove;

  const _ItemRow({
    super.key,
    required this.item,
    required this.categories,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  late final TextEditingController _descCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _quantityCtrl;
  late int? _categoryId;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController(text: widget.item.description);
    _amountCtrl = TextEditingController(text: widget.item.amount.toStringAsFixed(2));
    _quantityCtrl = TextEditingController(text: widget.item.quantity.toString());
    _categoryId = widget.item.categoryId;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _quantityCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(ReceiptItemDraft(
      description: _descCtrl.text.trim(),
      amount: double.tryParse(_amountCtrl.text.trim()) ?? widget.item.amount,
      quantity: int.tryParse(_quantityCtrl.text.trim()) ?? widget.item.quantity,
      categoryId: _categoryId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _descCtrl,
                  onChanged: (_) => _emit(),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Item description',
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: _categoryId,
                    isDense: true,
                    icon: const Icon(Icons.expand_more, size: 14, color: Color(0xFF9CA3AF)),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Uncategorized')),
                      for (final c in widget.categories)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) {
                      setState(() => _categoryId = v);
                      _emit();
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 28,
            child: TextField(
              controller: _quantityCtrl,
              onChanged: (_) => _emit(),
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
          const Text('×', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          SizedBox(
            width: 64,
            child: TextField(
              controller: _amountCtrl,
              onChanged: (_) => _emit(),
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14, color: Color(0xFF9CA3AF)),
            onPressed: widget.onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
