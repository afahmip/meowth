import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/receipt.dart';

class ReceiptApi {
  final String baseUrl;

  const ReceiptApi(this.baseUrl);

  // Polls the async job(s) behind a batch of images uploaded together via
  // ReceiptUploadManager — the actual upload happens out-of-band through
  // background_downloader, not through this client.
  Future<List<ReceiptJobStatus>> listJobs(String batchId) async {
    final uri = Uri.parse('$baseUrl/receipts/jobs')
        .replace(queryParameters: {'batch_id': batchId});
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception(res.body.isNotEmpty ? res.body.trim() : 'Failed to load upload status');
    }
    final data = jsonDecode(res.body) as List;
    return data.map((e) => ReceiptJobStatus.fromJson(e)).toList();
  }

  // Resets a job that uploaded successfully but failed analysis back to
  // queued — the server already has the image bytes, so no re-upload here.
  Future<void> retryJob(int jobId) async {
    final res = await http.post(Uri.parse('$baseUrl/receipts/jobs/$jobId/retry'));
    if (res.statusCode != 204) {
      throw Exception(res.body.isNotEmpty ? res.body.trim() : 'Failed to retry upload');
    }
  }

  Future<void> assignTransaction(int receiptId, int transactionId) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/receipts/$receiptId/transaction'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'transaction_id': transactionId}),
    );
    if (res.statusCode != 204) throw Exception('Failed to link transaction');
  }

  Future<List<ReceiptListItem>> list() async {
    final res = await http.get(Uri.parse('$baseUrl/receipts'));
    if (res.statusCode != 200) {
      throw Exception(res.body.isNotEmpty ? res.body.trim() : 'Failed to load receipts');
    }
    final data = jsonDecode(res.body) as List;
    return data.map((e) => ReceiptListItem.fromJson(e)).toList();
  }

  // Attaches a photo directly to an already-saved transaction, skipping the
  // scan-and-review flow entirely (the transaction's fields are already
  // known, so there's nothing to extract or confirm).
  Future<void> uploadReceipt(int transactionId, File image) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/transactions/$transactionId/receipt'),
    )..files.add(await http.MultipartFile.fromPath('image', image.path));
    final streamed = await request.send();
    if (streamed.statusCode != 201) {
      final body = await streamed.stream.bytesToString();
      throw Exception(body.isNotEmpty ? body.trim() : 'Failed to upload receipt');
    }
  }

  Future<void> discard(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/receipts/$id'));
    if (res.statusCode != 204) {
      throw Exception(res.body.isNotEmpty ? res.body.trim() : 'Failed to discard receipt');
    }
  }
}
