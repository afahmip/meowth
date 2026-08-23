import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/receipt.dart';

class ReceiptApi {
  final String baseUrl;

  const ReceiptApi(this.baseUrl);

  Future<ReceiptAnalysis> analyze(File image) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/receipts/analyze'))
          ..files.add(await http.MultipartFile.fromPath('image', image.path));
    final streamed = await request.send().timeout(const Duration(minutes: 5));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 201) {
      throw Exception(res.body.isNotEmpty ? res.body.trim() : 'Failed to analyze receipt');
    }
    return ReceiptAnalysis.fromJson(jsonDecode(res.body));
  }

  Future<void> assignTransaction(int receiptId, int transactionId) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/receipts/$receiptId/transaction'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'transaction_id': transactionId}),
    );
    if (res.statusCode != 204) throw Exception('Failed to link transaction');
  }
}
