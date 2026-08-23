import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/transaction.dart';

class TransactionApi {
  final String baseUrl;

  const TransactionApi(this.baseUrl);

  Future<List<Transaction>> list() async {
    final res = await http.get(Uri.parse('$baseUrl/transactions'));
    if (res.statusCode != 200) throw Exception('Failed to load transactions');
    final List data = jsonDecode(res.body);
    return data.map((e) => Transaction.fromJson(e)).toList();
  }

  Future<int> create(TransactionInput input) async {
    final res = await http.post(
      Uri.parse('$baseUrl/transactions'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(input.toJson()),
    );
    if (res.statusCode != 201) throw Exception('Failed to create transaction');
    return jsonDecode(res.body)['id'];
  }

  Future<void> update(int id, TransactionInput input) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/transactions/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(input.toJson()),
    );
    if (res.statusCode != 204) throw Exception('Failed to update transaction');
  }

  Future<void> delete(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/transactions/$id'));
    if (res.statusCode != 204) throw Exception('Failed to delete transaction');
  }
}
