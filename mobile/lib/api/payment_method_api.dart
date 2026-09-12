import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/payment_method.dart';

class PaymentMethodApi {
  final String baseUrl;

  const PaymentMethodApi(this.baseUrl);

  Future<List<PaymentMethod>> list() async {
    final res = await http.get(Uri.parse('$baseUrl/payment-methods'));
    if (res.statusCode != 200) throw Exception('Failed to load payment methods');
    final List data = jsonDecode(res.body);
    return data.map((e) => PaymentMethod.fromJson(e)).toList();
  }

  Future<int> create(String name, {String emoji = '', String type = 'cash'}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/payment-methods'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'emoji': emoji, 'type': type}),
    );
    if (res.statusCode != 201) {
      throw Exception(res.body.isNotEmpty ? res.body.trim() : 'Failed to create payment method');
    }
    return jsonDecode(res.body)['id'];
  }

  Future<void> update(int id, String name, {String emoji = '', String type = ''}) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/payment-methods/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'emoji': emoji, 'type': type}),
    );
    if (res.statusCode != 204) {
      throw Exception(res.body.isNotEmpty ? res.body.trim() : 'Failed to update payment method');
    }
  }

  Future<void> delete(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/payment-methods/$id'));
    if (res.statusCode != 204) {
      throw Exception(res.body.isNotEmpty ? res.body.trim() : 'Failed to delete payment method');
    }
  }
}
