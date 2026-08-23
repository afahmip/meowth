import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/summary.dart';
import '../models/transaction.dart';

class TransactionApi {
  final String baseUrl;

  const TransactionApi(this.baseUrl);

  Future<List<Transaction>> list({
    String? categoryId,
    String? from,
    String? to,
    String? keyword,
  }) async {
    final params = <String, String>{
      if (categoryId != null) 'category_id': categoryId,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (keyword != null && keyword.isNotEmpty) 'q': keyword,
    };
    final uri = Uri.parse('$baseUrl/transactions')
        .replace(queryParameters: params.isEmpty ? null : params);
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('Failed to load transactions');
    final List data = jsonDecode(res.body);
    return data.map((e) => Transaction.fromJson(e)).toList();
  }

  Future<TransactionSummary> summary({String? from, String? to}) async {
    final params = <String, String>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    };
    final uri = Uri.parse('$baseUrl/transactions/summary')
        .replace(queryParameters: params.isEmpty ? null : params);
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('Failed to load summary');
    return TransactionSummary.fromJson(jsonDecode(res.body));
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
