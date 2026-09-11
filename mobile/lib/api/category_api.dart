import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/category.dart';

class CategoryApi {
  final String baseUrl;

  const CategoryApi(this.baseUrl);

  Future<List<Category>> list() async {
    final res = await http.get(Uri.parse('$baseUrl/categories'));
    if (res.statusCode != 200) throw Exception('Failed to load categories');
    final List data = jsonDecode(res.body);
    return data.map((e) => Category.fromJson(e)).toList();
  }
}
