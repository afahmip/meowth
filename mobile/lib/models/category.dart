class Category {
  final int id;
  final String name;
  final String emoji;

  const Category({required this.id, required this.name, this.emoji = ''});

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'],
        name: j['name'] ?? '',
        emoji: j['emoji'] ?? '',
      );

  // Prefixes the name with its emoji wherever a category is shown as plain
  // text (dropdowns, tags) — falls back to just the name when unset.
  String get label => emoji.isNotEmpty ? '$emoji $name' : name;
}
