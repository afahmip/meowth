class PaymentMethod {
  final int id;
  final String name;
  final String emoji;
  final String type;

  const PaymentMethod({
    required this.id,
    required this.name,
    this.emoji = '',
    this.type = 'cash',
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> j) => PaymentMethod(
        id: j['id'],
        name: j['name'] ?? '',
        emoji: j['emoji'] ?? '',
        type: j['type'] ?? 'cash',
      );

  bool get isCredit => type == 'credit';

  // Prefixes the name with its emoji wherever a payment method is shown as
  // plain text (dropdowns, rows) — falls back to just the name when unset.
  String get label => emoji.isNotEmpty ? '$emoji $name' : name;
}
