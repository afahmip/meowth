import 'package:flutter/material.dart';
import '../api/category_api.dart';
import '../api/transaction_api.dart';
import '../config.dart';
import '../models/category.dart';
import '../models/transaction.dart';

// A row in the items editor. `id` is null for a row the user just added
// that doesn't exist on the server yet, which is how submit tells "add"
// apart from "update" for each row.
class _FormItem {
  final int? id;
  final TextEditingController descCtrl;
  final TextEditingController amountCtrl;
  final TextEditingController qtyCtrl;

  _FormItem({this.id, String description = '', double amount = 0, int quantity = 1})
      : descCtrl = TextEditingController(text: description),
        amountCtrl = TextEditingController(text: amount == 0 ? '' : amount.toStringAsFixed(2)),
        qtyCtrl = TextEditingController(text: quantity.toString());

  void dispose() {
    descCtrl.dispose();
    amountCtrl.dispose();
    qtyCtrl.dispose();
  }
}

class TransactionFormScreen extends StatefulWidget {
  final TransactionApi api;
  final Transaction? transaction;

  const TransactionFormScreen({super.key, required this.api, this.transaction});

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final CategoryApi _categoryApi;
  late final TextEditingController _merchantCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _currencyCtrl;
  late String _type;
  late String _spendingType;
  late int _importanceLevel;
  int? _categoryId;
  List<Category> _categories = [];
  DateTime? _date;
  late List<_FormItem> _items;
  final List<int> _removedItemIds = [];
  bool _loading = false;

  bool get _isEdit => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _categoryApi = CategoryApi(AppConfig.baseUrl);
    _categoryApi.list().then((cats) {
      if (mounted) setState(() => _categories = cats);
    }).catchError((_) {});
    _merchantCtrl = TextEditingController(text: t?.merchant ?? '');
    _amountCtrl = TextEditingController(
        text: t != null ? t.amount.toStringAsFixed(0) : '');
    _currencyCtrl = TextEditingController(text: t?.currency ?? 'IDR');
    _type = t?.type ?? 'expense';
    _spendingType = t?.spendingType ?? 'one_time';
    _importanceLevel = t?.importanceLevel ?? 3;
    _categoryId = t?.categoryId;
    if (t?.transactionDate != null) {
      _date = DateTime.tryParse(t!.transactionDate!);
    }
    _items = (t?.items ?? [])
        .map((i) => _FormItem(id: i.id, description: i.description, amount: i.amount, quantity: i.quantity))
        .toList();
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _amountCtrl.dispose();
    _currencyCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _addItem() {
    setState(() => _items.add(_FormItem()));
  }

  void _removeItem(int index) {
    final item = _items[index];
    if (item.id != null) _removedItemIds.add(item.id!);
    setState(() {
      _items.removeAt(index);
    });
    item.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      // Rows left blank (no description typed) are dropped rather than
      // submitted as junk items.
      final liveItems = _items.where((i) => i.descCtrl.text.trim().isNotEmpty).toList();

      if (_isEdit) {
        final txnId = widget.transaction!.id;
        await widget.api.update(
          txnId,
          TransactionInput(
            merchant: _merchantCtrl.text.trim(),
            amount: double.parse(_amountCtrl.text.trim()),
            currency: _currencyCtrl.text.trim().toUpperCase(),
            type: _type,
            spendingType: _spendingType,
            importanceLevel: _importanceLevel,
            transactionDate: _date?.toIso8601String().substring(0, 10),
            categoryId: _categoryId,
          ),
        );

        for (final id in _removedItemIds) {
          await widget.api.deleteItem(txnId, id);
        }

        final newItems = <TransactionItemInput>[];
        for (final item in liveItems) {
          final input = TransactionItemInput(
            description: item.descCtrl.text.trim(),
            amount: double.tryParse(item.amountCtrl.text.trim()) ?? 0,
            quantity: int.tryParse(item.qtyCtrl.text.trim()) ?? 1,
          );
          if (item.id != null) {
            await widget.api.updateItem(txnId, item.id!, input);
          } else {
            newItems.add(input);
          }
        }
        await widget.api.addItems(txnId, newItems);
      } else {
        await widget.api.create(TransactionInput(
          merchant: _merchantCtrl.text.trim(),
          amount: double.parse(_amountCtrl.text.trim()),
          currency: _currencyCtrl.text.trim().toUpperCase(),
          type: _type,
          spendingType: _spendingType,
          importanceLevel: _importanceLevel,
          transactionDate: _date?.toIso8601String().substring(0, 10),
          categoryId: _categoryId,
          items: liveItems
              .map((item) => TransactionItemInput(
                    description: item.descCtrl.text.trim(),
                    amount: double.tryParse(item.amountCtrl.text.trim()) ?? 0,
                    quantity: int.tryParse(item.qtyCtrl.text.trim()) ?? 1,
                  ))
              .toList(),
        ));
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _isEdit ? 'Edit Transaction' : 'New Transaction',
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _label('Type'),
            const SizedBox(height: 8),
            _typeSelector(),
            const SizedBox(height: 16),
            _label('Spending Type'),
            const SizedBox(height: 8),
            _spendingTypeSelector(),
            const SizedBox(height: 16),
            _label('Merchant / Description'),
            const SizedBox(height: 8),
            _textField(
              controller: _merchantCtrl,
              hint: 'e.g. Starbucks',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Amount'),
                      const SizedBox(height: 8),
                      _textField(
                        controller: _amountCtrl,
                        hint: '0',
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (double.tryParse(v) == null) return 'Invalid';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Currency'),
                      const SizedBox(height: 8),
                      _textField(
                        controller: _currencyCtrl,
                        hint: 'IDR',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _label('Date'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 16, color: Color(0xFF6B7280)),
                    const SizedBox(width: 8),
                    Text(
                      _date != null
                          ? _date!.toIso8601String().substring(0, 10)
                          : 'Select date',
                      style: TextStyle(
                        color: _date != null
                            ? const Color(0xFF111827)
                            : const Color(0xFF9CA3AF),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _label('Category'),
            const SizedBox(height: 8),
            _categoryDropdown(),
            const SizedBox(height: 16),
            _label('Importance'),
            const SizedBox(height: 8),
            _importanceSelector(),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _label('Items'),
                TextButton.icon(
                  onPressed: _addItem,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Item', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _items.length; i++) _itemRow(i),
            const SizedBox(height: 32),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_isEdit ? 'Save Changes' : 'Create Transaction'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryDropdown() {
    // Guards against passing a value DropdownButtonFormField doesn't have a
    // matching item for yet, e.g. right after opening the edit form, before
    // the category list has finished loading.
    final value = _categories.any((c) => c.id == _categoryId) ? _categoryId : null;
    return DropdownButtonFormField<int?>(
      value: value,
      isExpanded: true,
      items: [
        const DropdownMenuItem(value: null, child: Text('Uncategorized')),
        for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
      ],
      onChanged: (v) => setState(() => _categoryId = v),
      decoration: _fieldDecoration(),
    );
  }

  InputDecoration _fieldDecoration() => InputDecoration(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF111827)),
        ),
      );

  Widget _itemRow(int index) {
    final item = _items[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: item.descCtrl,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Item description',
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: TextField(
              controller: item.qtyCtrl,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none),
            ),
          ),
          const Text('×', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          SizedBox(
            width: 64,
            child: TextField(
              controller: item.amountCtrl,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
            onPressed: () => _removeItem(index),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Color(0xFF374151),
        ),
      );

  Widget _textField({
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(fontSize: 15, color: Color(0xFF111827)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF111827)),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDC2626)),
          ),
        ),
      );

  Widget _spendingTypeSelector() => Row(
        children: [
          for (final entry in const {
            'one_time': 'One-time',
            'living_cost': 'Living Cost',
          }.entries)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _spendingType = entry.key),
                child: Container(
                  margin: EdgeInsets.only(
                      right: entry.key != 'living_cost' ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _spendingType == entry.key
                        ? const Color(0xFF111827)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _spendingType == entry.key
                          ? const Color(0xFF111827)
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Text(
                    entry.value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _spendingType == entry.key
                          ? Colors.white
                          : const Color(0xFF374151),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );

  Widget _importanceSelector() => Row(
        children: [
          for (var level = 1; level <= 5; level++)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _importanceLevel = level),
                child: Container(
                  margin: EdgeInsets.only(right: level != 5 ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _importanceLevel == level
                        ? const Color(0xFF111827)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _importanceLevel == level
                          ? const Color(0xFF111827)
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Text(
                    '$level',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _importanceLevel == level
                          ? Colors.white
                          : const Color(0xFF374151),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );

  Widget _typeSelector() => Row(
        children: [
          for (final type in ['expense', 'income', 'transfer'])
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _type = type),
                child: Container(
                  margin: EdgeInsets.only(
                      right: type != 'transfer' ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _type == type
                        ? const Color(0xFF111827)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _type == type
                          ? const Color(0xFF111827)
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Text(
                    type[0].toUpperCase() + type.substring(1),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _type == type
                          ? Colors.white
                          : const Color(0xFF374151),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
}
