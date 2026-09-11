class Category {
  final int id;
  final String name;

  const Category({required this.id, required this.name});

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'],
        name: j['name'] ?? '',
      );
}
