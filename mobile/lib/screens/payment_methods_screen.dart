import 'package:flutter/material.dart';
import '../api/payment_method_api.dart';
import '../config.dart';
import '../models/payment_method.dart';
import '../widgets/shimmer_placeholder.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  late final PaymentMethodApi _api;
  List<PaymentMethod> _methods = [];
  bool _loading = true;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _api = PaymentMethodApi(AppConfig.baseUrl);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final methods = await _api.list();
      setState(() => _methods = methods);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<(String, String, String)?> _promptPaymentMethod({
    required String title,
    required String actionLabel,
    String initialName = '',
    String initialEmoji = '',
    String initialType = 'cash',
  }) {
    final nameController = TextEditingController(text: initialName);
    final emojiController = TextEditingController(text: initialEmoji);
    String type = initialType;
    return showDialog<(String, String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: TextField(
                      controller: emojiController,
                      autofocus: initialName.isEmpty,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(hintText: '💳'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: nameController,
                      autofocus: initialName.isNotEmpty,
                      decoration: const InputDecoration(hintText: 'Payment method name'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final entry in const {'credit': 'Credit', 'cash': 'Cash'}.entries)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setDialogState(() => type = entry.key),
                        child: Container(
                          margin: EdgeInsets.only(right: entry.key != 'cash' ? 8 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: type == entry.key ? const Color(0xFF111827) : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: type == entry.key
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
                              color: type == entry.key ? Colors.white : const Color(0xFF374151),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                  ctx, (nameController.text.trim(), emojiController.text.trim(), type)),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPaymentMethod() async {
    final result = await _promptPaymentMethod(title: 'New Payment Method', actionLabel: 'Add');
    if (result == null || result.$1.isEmpty) return;

    setState(() => _saving = true);
    try {
      await _api.create(result.$1, emoji: result.$2, type: result.$3);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editPaymentMethod(PaymentMethod m) async {
    final result = await _promptPaymentMethod(
      title: 'Edit Payment Method',
      actionLabel: 'Save',
      initialName: m.name,
      initialEmoji: m.emoji,
      initialType: m.type,
    );
    if (result == null || result.$1.isEmpty) return;
    if (result.$1 == m.name && result.$2 == m.emoji && result.$3 == m.type) return;

    setState(() => _saving = true);
    try {
      await _api.update(m.id, result.$1, emoji: result.$2, type: result.$3);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deletePaymentMethod(PaymentMethod m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Payment Method'),
        content: Text(
          'Delete "${m.label}"? Transactions using it will keep no payment method.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await _api.delete(m.id);
      await _load();
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
        title: const Text(
          'Payment Methods',
          style: TextStyle(
            color: Color(0xFF111827),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _saving ? null : _addPaymentMethod,
        backgroundColor: const Color(0xFF111827),
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _methods.isEmpty) {
      return ShimmerPlaceholder(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          itemCount: 8,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, __) => const _PaymentMethodRowSkeleton(),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_outlined, size: 48, color: Color(0xFF9CA3AF)),
            const SizedBox(height: 12),
            const Text(
              'Could not load payment methods',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_methods.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.payments_outlined, size: 48, color: Color(0xFF9CA3AF)),
              const SizedBox(height: 12),
              const Text(
                'No payment methods yet',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tap + to add your first payment method',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
        itemCount: _methods.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final m = _methods[i];
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _saving ? null : () => _editPaymentMethod(m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: m.emoji.isNotEmpty
                            ? Text(m.emoji, style: const TextStyle(fontSize: 16))
                            : const Icon(Icons.payments_outlined, size: 16, color: Color(0xFF2563EB)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          m.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: m.isCredit
                              ? const Color(0xFF2563EB).withValues(alpha: 0.1)
                              : const Color(0xFF16A34A).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          m.isCredit ? 'Credit' : 'Cash',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: m.isCredit ? const Color(0xFF2563EB) : const Color(0xFF16A34A),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFF9CA3AF)),
                        onPressed: _saving ? null : () => _deletePaymentMethod(m),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PaymentMethodRowSkeleton extends StatelessWidget {
  const _PaymentMethodRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ShimmerBox(width: 32, height: 32, borderRadius: BorderRadius.circular(8)),
          const SizedBox(width: 12),
          const ShimmerBox(width: 100, height: 15),
          const Spacer(),
          ShimmerBox(width: 44, height: 18, borderRadius: BorderRadius.circular(20)),
          const SizedBox(width: 12),
          const ShimmerBox(width: 20, height: 20),
        ],
      ),
    );
  }
}
