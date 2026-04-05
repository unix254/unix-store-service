import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/staff.dart';
import '../models/staff_member.dart';
import '../models/supplier.dart';
import '../models/ledger_entry.dart';
import '../models/inventory_item.dart';
import '../models/requisition.dart';
import '../models/pos_product.dart';
import '../models/yield_config.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  // In Flutter web, Uri.base gives us the server's origin automatically.
  // When served via Express on port 5000, this resolves correctly in all environments.
  Uri _uri(String path) {
    if (kIsWeb) return Uri.base.resolve(path);
    return Uri.parse('http://localhost:5000$path');
  }

  Map<String, String> get _headers => {'Content-Type': 'application/json'};

  Future<dynamic> _get(String path) async {
    final res = await http.get(_uri(path), headers: _headers);
    return _parse(res);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final res = await http.post(_uri(path), headers: _headers, body: jsonEncode(body));
    return _parse(res);
  }

  Future<dynamic> _patch(String path, Map<String, dynamic> body) async {
    final res = await http.patch(_uri(path), headers: _headers, body: jsonEncode(body));
    return _parse(res);
  }

  Future<dynamic> _put(String path, Map<String, dynamic> body) async {
    final res = await http.put(_uri(path), headers: _headers, body: jsonEncode(body));
    return _parse(res);
  }

  Future<dynamic> _delete(String path) async {
    final res = await http.delete(_uri(path), headers: _headers);
    return _parse(res);
  }

  dynamic _parse(http.Response res) {
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      final msg = (body is Map && body['error'] != null)
          ? body['error'] as String
          : 'Request failed (${res.statusCode})';
      throw ApiException(msg, res.statusCode);
    }
    return body;
  }

  // ── Auth ────────────────────────────────────────────────────

  Future<Staff> verifyPin(String pin) async {
    final data = await _post('/api/auth/pin', {'pin': pin});
    return Staff.fromJson(data as Map<String, dynamic>);
  }

  Future<List<StaffMember>> getAllStaff() async {
    final data = await _get('/api/auth/staff');
    return (data as List).map((e) => StaffMember.fromJson(e)).toList();
  }

  Future<String> createStaff(Map<String, dynamic> body) async {
    final data = await _post('/api/auth/staff', body);
    return data['id'] as String;
  }

  Future<void> updateStaff(String id, Map<String, dynamic> body) async {
    await _put('/api/auth/staff/$id', body);
  }

  Future<void> toggleStaffActive(String id) async {
    await _patch('/api/auth/staff/$id/toggle', {});
  }

  Future<void> deleteStaff(String id) async {
    await _delete('/api/auth/staff/$id');
  }

  // ── Suppliers ───────────────────────────────────────────────

  Future<List<Supplier>> getSuppliers() async {
    final data = await _get('/api/suppliers');
    return (data as List).map((e) => Supplier.fromJson(e)).toList();
  }

  Future<String> createSupplier(Map<String, dynamic> body) async {
    final data = await _post('/api/suppliers', body);
    return data['id'] as String;
  }

  Future<void> updateSupplier(String id, Map<String, dynamic> body) async {
    await _put('/api/suppliers/$id', body);
  }

  Future<void> deleteSupplier(String id) async {
    await _delete('/api/suppliers/$id');
  }

  Future<List<LedgerEntry>> getSupplierLedger(String supplierId) async {
    final data = await _get('/api/suppliers/$supplierId/ledger');
    return (data as List).map((e) => LedgerEntry.fromJson(e)).toList();
  }

  Future<String> addLedgerEntry(String supplierId, Map<String, dynamic> body) async {
    final data = await _post('/api/suppliers/$supplierId/ledger', body);
    return data['id'] as String;
  }

  Future<Map<String, dynamic>> getOrderMessage(
      String supplierId, List<Map<String, dynamic>> items, {String? note}) async {
    final data = await _post('/api/suppliers/$supplierId/order', {
      'items': items,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getUpcomingDebt() async {
    final data = await _get('/api/suppliers/alerts/upcoming-debt');
    return (data as List).cast<Map<String, dynamic>>();
  }

  // ── Inventory ───────────────────────────────────────────────

  Future<List<InventoryItem>> getInventory() async {
    final data = await _get('/api/inventory');
    return (data as List).map((e) => InventoryItem.fromJson(e)).toList();
  }

  Future<List<InventoryItem>> getReorderAlerts() async {
    final data = await _get('/api/inventory/alerts/reorder');
    return (data as List).map((e) => InventoryItem.fromJson(e)).toList();
  }

  Future<String> createInventoryItem(Map<String, dynamic> body) async {
    final data = await _post('/api/inventory', body);
    return data['id'] as String;
  }

  Future<void> updateInventoryItem(String id, Map<String, dynamic> body) async {
    await _put('/api/inventory/$id', body);
  }

  Future<void> deleteInventoryItem(String id) async {
    await _delete('/api/inventory/$id');
  }

  /// Adjust stock level: positive delta = receive delivery, negative = correction
  Future<void> adjustStock(String id, double delta, {String? reason}) async {
    await _patch('/api/inventory/$id/adjust', {
      'delta': delta,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  // ── Requisitions ────────────────────────────────────────────

  Future<List<Requisition>> getRequisitions({String? status}) async {
    final path = status != null
        ? '/api/requisitions?status=${Uri.encodeComponent(status)}'
        : '/api/requisitions';
    final data = await _get(path);
    return (data as List).map((e) => Requisition.fromJson(e)).toList();
  }

  Future<List<Requisition>> getPendingRequisitions() async {
    final data = await _get('/api/requisitions/pending');
    return (data as List).map((e) => Requisition.fromJson(e)).toList();
  }

  Future<String> submitRequisition({
    required String inventoryItemId,
    required double quantity,
    required String unitOfMeasure,
    required String requestedBy,
    required String purpose,
    String? notes,
  }) async {
    final data = await _post('/api/requisitions', {
      'inventory_item_id': inventoryItemId,
      'quantity':          quantity,
      'unit_of_measure':   unitOfMeasure,
      'requested_by':      requestedBy,
      'purpose':           purpose,
      'notes':             notes,
    });
    return data['id'] as String;
  }

  Future<void> issueRequisition(String id, String issuedBy) async {
    await _patch('/api/requisitions/$id/issue', {'issued_by': issuedBy});
  }

  Future<void> rejectRequisition(String id) async {
    await _patch('/api/requisitions/$id/reject', {});
  }

  // ── POS (read-only) ─────────────────────────────────────────

  Future<List<PosProduct>> getPosProducts() async {
    final data = await _get('/api/pos/products');
    return (data as List).map((e) => PosProduct.fromJson(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getTodaySales() async {
    final data = await _get('/api/pos/sales/today');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getVarianceToday() async {
    final data = await _get('/api/pos/variance/today');
    return (data as List).cast<Map<String, dynamic>>();
  }

  // ── Yield Config ────────────────────────────────────────────

  Future<List<YieldConfig>> getYieldConfigs() async {
    final data = await _get('/api/yield');
    return (data as List).map((e) => YieldConfig.fromJson(e)).toList();
  }

  Future<String> createYieldConfig(Map<String, dynamic> body) async {
    final data = await _post('/api/yield', body);
    return data['id'] as String;
  }

  Future<void> updateYieldConfig(String id, Map<String, dynamic> body) async {
    await _put('/api/yield/$id', body);
  }

  Future<void> deleteYieldConfig(String id) async {
    await _delete('/api/yield/$id');
  }
}
