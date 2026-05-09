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
import '../models/feature_flag.dart';
import '../models/timeline_entry.dart';

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

  Future<List<LedgerEntry>> getSupplierLedger(
      String supplierId, {String? from, String? to}) async {
    String path = '/api/suppliers/$supplierId/ledger';
    final params = <String>[];
    if (from != null) params.add('from=$from');
    if (to   != null) params.add('to=$to');
    if (params.isNotEmpty) path += '?${params.join('&')}';
    final data = await _get(path);
    return (data as List).map((e) => LedgerEntry.fromJson(e)).toList();
  }

  Future<String> addLedgerEntry(String supplierId, Map<String, dynamic> body) async {
    final data = await _post('/api/suppliers/$supplierId/ledger', body);
    return data['id'] as String;
  }

  /// Phase 7: Record a Cash-In (bank withdrawal / float top-up) on an internal supplier's ledger.
  Future<String> recordCashIn(
    String supplierId, {
    required double amount,
    required String transactionDate,
    String? description,
    String? referenceDoc,
  }) async {
    return addLedgerEntry(supplierId, {
      'transaction_type': 'CASH_IN',
      'amount':           amount,
      'transaction_date': transactionDate,
      if (description != null && description.isNotEmpty) 'description': description,
      if (referenceDoc != null && referenceDoc.isNotEmpty) 'reference_doc': referenceDoc,
    });
  }

  Future<Map<String, dynamic>> getOrderMessage(
      String supplierId, List<Map<String, dynamic>> items, {String? note}) async {
    final data = await _post('/api/suppliers/$supplierId/order', {
      'items': items,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getSupplierStatement(String supplierId, {int days = 30}) async {
    final data = await _get('/api/suppliers/$supplierId/statement?days=$days');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getSupplierStatementWhatsApp(
      String supplierId, {int days = 30, String? from, String? to}) async {
    String path = '/api/suppliers/$supplierId/statement/whatsapp';
    if (from != null && to != null) {
      path += '?from=$from&to=$to';
    } else {
      path += '?days=$days';
    }
    final data = await _get(path);
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

  /// Adjust stock level: positive delta = receive delivery, negative = correction.
  /// For deliveries, supply [supplierId] + [totalCost] to auto-post a PURCHASE
  /// entry on the supplier ledger (zero-friction debt linking).
  ///
  /// Returns the raw response map — callers should inspect [result['priceWarning']]
  /// which is non-null when a delivery caused a cost increase affecting POS items.
  Future<Map<String, dynamic>?> adjustStock(
    String id,
    double delta, {
    String? reason,
    String? changedBy,
    double? newCostPerUnit,
    String? supplierId,
    double? totalCost,
  }) async {
    final result = await _patch('/api/inventory/$id/adjust', {
      'delta': delta,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      if (changedBy != null) 'changed_by': changedBy,
      if (newCostPerUnit != null) 'new_cost_per_unit': newCostPerUnit,
      if (supplierId != null) 'supplier_id': supplierId,
      if (totalCost != null && totalCost > 0) 'total_cost': totalCost,
    });
    return result as Map<String, dynamic>?;
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
    String? requesterLocation,
  }) async {
    final data = await _post('/api/requisitions', {
      'inventory_item_id':  inventoryItemId,
      'quantity':           quantity,
      'unit_of_measure':    unitOfMeasure,
      'requested_by':       requestedBy,
      'purpose':            purpose,
      'notes':              notes,
      if (requesterLocation != null) 'requester_location': requesterLocation,
    });
    return data['id'] as String;
  }

  /// Phase 11: Submit a "new item request" — inventory_item_id will be NULL on the server.
  /// The server stores a structured note: [NEW ITEM REQUEST] Name: ... | Qty: ... | Notes: ...
  Future<String> submitNewItemRequest({
    required String requestedBy,
    required String itemName,
    required String unit,
    required double qty,
    required String purpose,
    String? notes,
  }) async {
    final data = await _post('/api/requisitions', {
      'item_name':    itemName,
      'unit':         unit,
      'quantity':     qty,
      'requested_by': requestedBy,
      'purpose':      purpose,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return data['id'] as String;
  }

  /// Phase 8: [issuedQuantity] lets the storekeeper issue a partial/adjusted amount.
  /// [issueNotes] explains the adjustment to the requester.
  Future<void> issueRequisition(
    String id,
    String issuedBy, {
    double? issuedQuantity,
    String? issueNotes,
  }) async {
    await _patch('/api/requisitions/$id/issue', {
      'issued_by': issuedBy,
      if (issuedQuantity != null) 'issued_quantity': issuedQuantity,
      if (issueNotes != null && issueNotes.isNotEmpty) 'issue_notes': issueNotes,
    });
  }

  /// Phase 8: [reason] is stored as issue_notes so the requester sees why it was rejected.
  Future<void> rejectRequisition(String id, {String? reason, String? rejectedBy}) async {
    await _patch('/api/requisitions/$id/reject', {
      if (reason != null && reason.isNotEmpty) 'reject_reason': reason,
      if (rejectedBy != null && rejectedBy.isNotEmpty) 'rejected_by': rejectedBy,
    });
  }

  // ── Requisition Timeline ────────────────────────────────────

  Future<List<TimelineEntry>> getRequisitionTimeline(String id) async {
    final data = await _get('/api/requisitions/$id/timeline');
    return (data as List).map((e) => TimelineEntry.fromJson(e)).toList();
  }

  Future<void> addTimelineComment(String reqId, String actorName, String message) async {
    await _post('/api/requisitions/$reqId/timeline', {
      'actor_name': actorName,
      'message':    message,
    });
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

  Future<List<Map<String, dynamic>>> getVarianceRange(String from, String to) async {
    final data = await _get('/api/pos/variance/range?from=$from&to=$to');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getIssuedCostToday() async {
    final data = await _get('/api/pos/issues-cost/today');
    return data as Map<String, dynamic>;
  }

  // ── Inventory (M6 additions) ────────────────────────────────

  Future<List<Map<String, dynamic>>> getDraftPO() async {
    final data = await _get('/api/inventory/draft-po');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> logWaste({
    required String inventoryItemId,
    required double quantity,
    required String loggedBy,
    String? notes,
    String? requesterLocation,
  }) async {
    await _post('/api/inventory/waste', {
      'inventory_item_id':   inventoryItemId,
      'quantity':            quantity,
      'logged_by':           loggedBy,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (requesterLocation != null) 'requester_location': requesterLocation,
    });
  }

  Future<List<Map<String, dynamic>>> getInflationSummary({int days = 30}) async {
    final data = await _get('/api/inventory/inflation-summary?days=$days');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> sendPriceImpact({String? phone, int days = 30}) async {
    final data = await _post('/api/inventory/send-price-impact', {
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      'days': days,
    });
    return data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getCostHistory(String itemId) async {
    final data = await _get('/api/inventory/cost-history/$itemId');
    return (data as List).cast<Map<String, dynamic>>();
  }

  // ── Pay Runs ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPayRuns() async {
    final data = await _get('/api/pay-runs');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getTodayPayRun() async {
    final data = await _get('/api/pay-runs/today');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getPayRun(String id) async {
    final data = await _get('/api/pay-runs/$id');
    return data as Map<String, dynamic>;
  }

  Future<int> autoPopulatePayRun(String id) async {
    final data = await _post('/api/pay-runs/$id/auto-populate', {});
    return (data['added'] as num).toInt();
  }

  Future<void> addPayRunDetail(String runId, Map<String, dynamic> body) async {
    await _post('/api/pay-runs/$runId/details', body);
  }

  Future<void> updatePayRunDetail(String runId, String detailId, Map<String, dynamic> body) async {
    await _put('/api/pay-runs/$runId/details/$detailId', body);
  }

  Future<void> removePayRunDetail(String runId, String detailId) async {
    await _delete('/api/pay-runs/$runId/details/$detailId');
  }

  Future<void> submitPayRun(String id, String createdBy) async {
    await _patch('/api/pay-runs/$id/submit', {'created_by': createdBy});
  }

  Future<void> approvePayRun(String id) async {
    await _patch('/api/pay-runs/$id/approve', {});
  }

  /// Phase 7: Manager-led shortcut — transitions a Draft run directly to Approved,
  /// bypassing the Submitted / owner-WhatsApp-approval step.
  Future<void> finalizePayRun(String id) async {
    await _patch('/api/pay-runs/$id/finalize', {});
  }

  Future<Map<String, dynamic>> disbursePayRun(String id, String disbursedBy) async {
    final data = await _patch('/api/pay-runs/$id/disburse', {'disbursed_by': disbursedBy});
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> disbursePayRunDetail(
    String runId,
    String detailId, {
    required String disbursedBy,
    String? paymentSourceId,
    String? paymentReference,
  }) async {
    final data = await _patch(
      '/api/pay-runs/$runId/details/$detailId/disburse',
      {
        'disbursed_by': disbursedBy,
        if (paymentSourceId != null) 'payment_source_supplier_id': paymentSourceId,
        if (paymentReference != null) 'payment_reference': paymentReference,
      },
    );
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getPayRunWhatsApp(String id, {String? phone}) async {
    final path = phone != null
        ? '/api/pay-runs/$id/whatsapp?phone=${Uri.encodeComponent(phone)}'
        : '/api/pay-runs/$id/whatsapp';
    final data = await _get(path);
    return data as Map<String, dynamic>;
  }

  // ── Purchase Orders ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPurchaseOrders() async {
    final data = await _get('/api/purchase-orders');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getPurchaseOrder(String id) async {
    final data = await _get('/api/purchase-orders/$id');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> autoDraftPO(String createdBy) async {
    final data = await _post('/api/purchase-orders/auto-draft', {'created_by': createdBy});
    return data as Map<String, dynamic>;
  }

  Future<void> addPoDetail(String poId, Map<String, dynamic> body) async {
    await _post('/api/purchase-orders/$poId/details', body);
  }

  Future<void> updatePoDetail(String poId, String detailId, Map<String, dynamic> body) async {
    await _put('/api/purchase-orders/$poId/details/$detailId', body);
  }

  Future<void> removePoDetail(String poId, String detailId) async {
    await _delete('/api/purchase-orders/$poId/details/$detailId');
  }

  Future<Map<String, dynamic>> submitPO(String id) async {
    final data = await _patch('/api/purchase-orders/$id/submit', {});
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> approvePO(String id, String approvedBy) async {
    final data = await _patch('/api/purchase-orders/$id/approve', {'approved_by': approvedBy});
    return data as Map<String, dynamic>;
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

  // ── Procurement ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getInternalSuppliers() async {
    final data = await _get('/api/suppliers');
    return (data as List)
        .cast<Map<String, dynamic>>()
        .where((s) => (s['is_internal'] as num?)?.toInt() == 1)
        .toList();
  }

  Future<Map<String, dynamic>> generateProcurement(String generatedBy) async {
    final data = await _post('/api/procurement/generate', {'generated_by': generatedBy});
    return data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getProcurementLogs() async {
    final data = await _get('/api/procurement/logs');
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Phase 8: Build WhatsApp URLs from user-adjusted (or ad-hoc) procurement groups.
  /// [groups] is a list of { purchaser_name, purchaser_phone, items: [{ name, unit, qty }] }.
  Future<List<Map<String, dynamic>>> buildProcurementWhatsApp(
      List<Map<String, dynamic>> groups) async {
    final data = await _post('/api/procurement/build-whatsapp', {'groups': groups});
    return ((data as Map<String, dynamic>)['groups'] as List)
        .cast<Map<String, dynamic>>();
  }

  // ── Feature Flags ───────────────────────────────────────────

  Future<List<FeatureFlag>> getFeatureFlags() async {
    final data = await _get('/api/feature-flags');
    return (data as List)
        .map((e) => FeatureFlag.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateFeatureFlag(String key, bool enabled) async {
    await _put('/api/feature-flags/$key', {'enabled': enabled});
  }

  // ── Super Admin ─────────────────────────────────────────────

  /// Validates super admin credentials. Throws [ApiException] on failure.
  Future<void> superAdminLogin(String username, String password) async {
    await _post('/api/admin/super-login', {
      'username': username,
      'password': password,
    });
  }

  /// Wipes all transactional store_ tables. Credentials re-verified server-side.
  Future<Map<String, dynamic>> goLiveWipe(String username, String password) async {
    final data = await _post('/api/admin/go-live-wipe', {
      'username': username,
      'password': password,
    });
    return data as Map<String, dynamic>;
  }

  // ── Business Settings ───────────────────────────────────────

  Future<Map<String, String>> getSettings() async {
    final data = await _get('/api/settings');
    return (data as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v.toString()));
  }

  Future<void> updateSettings(Map<String, String> updates) async {
    await _patch('/api/settings', updates);
  }

  // ── Variance (v1.2 — dual-mode) ─────────────────────────────
  // Returns { mode: 'estimate'|'verified', from, to, station_id, rows: [...] }
  Future<Map<String, dynamic>> getVarianceRangeV2(
      String from, String to, {String? stationId}) async {
    String path = '/api/pos/variance/range?from=$from&to=$to';
    if (stationId != null) path += '&station_id=$stationId';
    final data = await _get(path);
    return data as Map<String, dynamic>;
  }

  // ── Stations ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getStations() async {
    final data = await _get('/api/stations');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<String> createStation(String name, {String? description}) async {
    final data = await _post('/api/stations', {
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
    });
    return data['id'] as String;
  }

  Future<void> updateStation(String id, String name, {String? description}) async {
    await _put('/api/stations/$id', {
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
    });
  }

  Future<void> toggleStation(String id) async {
    await _patch('/api/stations/$id/toggle', {});
  }

  Future<void> deleteStation(String id) async {
    await _delete('/api/stations/$id');
  }

  // ── Kitchen Counts ──────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getStationsSummary() async {
    final data = await _get('/api/kitchen-counts/stations-summary');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getActiveCountList(String stationId) async {
    final data = await _get('/api/kitchen-counts/active-list/$stationId');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getOpeningData(String stationId) async {
    final data = await _get('/api/kitchen-counts/opening-data/$stationId');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitClosingCount({
    required String stationId,
    required String countedBy,
    required List<Map<String, dynamic>> items,
  }) async {
    final data = await _post('/api/kitchen-counts/closing', {
      'station_id':  stationId,
      'counted_by':  countedBy,
      'items':       items,
    });
    return data as Map<String, dynamic>;
  }

  Future<void> submitOpeningCount({
    required String stationId,
    required String countedBy,
    required List<Map<String, dynamic>> items,
  }) async {
    await _post('/api/kitchen-counts/opening', {
      'station_id':  stationId,
      'counted_by':  countedBy,
      'items':       items,
    });
  }

  Future<void> confirmSnapshot(String snapshotId, String confirmedBy,
      {List<Map<String, dynamic>>? overrides}) async {
    await _patch('/api/kitchen-counts/$snapshotId/confirm', {
      'confirmed_by': confirmedBy,
      if (overrides != null && overrides.isNotEmpty) 'overrides': overrides,
    });
  }

  Future<Map<String, dynamic>> getKitchenLedger(
      String date, {String? stationId}) async {
    String path = '/api/kitchen-counts/ledger?date=$date';
    if (stationId != null) path += '&station_id=$stationId';
    final data = await _get(path);
    return data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getStationSnapshots(
      String stationId, {int days = 7}) async {
    final data = await _get('/api/kitchen-counts/snapshots/$stationId?days=$days');
    return (data as List).cast<Map<String, dynamic>>();
  }
}
