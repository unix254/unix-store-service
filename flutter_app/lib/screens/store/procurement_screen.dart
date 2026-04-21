import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../../services/api.dart';

final _kes    = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);
final _dtFmt  = DateFormat('dd MMM yyyy, HH:mm');

class ProcurementScreen extends StatefulWidget {
  final Staff staff;
  const ProcurementScreen({super.key, required this.staff});

  @override
  State<ProcurementScreen> createState() => _ProcurementScreenState();
}

class _ProcurementScreenState extends State<ProcurementScreen> {
  // Raw groups from the backend — converted to editable state on generate.
  List<_EditableGroup> _editableGroups = [];
  List<Map<String, dynamic>> _logs   = [];
  bool _generating   = false;
  bool _loadingLogs  = false;
  bool _sending      = false;
  String? _statusMsg;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loadingLogs = true);
    try {
      final logs = await ApiService.instance.getProcurementLogs();
      setState(() { _logs = logs; _loadingLogs = false; });
    } catch (_) {
      setState(() => _loadingLogs = false);
    }
  }

  Future<void> _generate() async {
    // Dispose any previous controllers before replacing state
    for (final g in _editableGroups) g.dispose();
    setState(() { _generating = true; _editableGroups = []; _statusMsg = null; });
    try {
      final result = await ApiService.instance.generateProcurement(widget.staff.name);
      final rawGroups = (result['groups'] as List?)
          ?.cast<Map<String, dynamic>>() ?? [];
      final msg = result['message'] as String?;
      final editable = rawGroups.map(_EditableGroup.fromMap).toList();
      setState(() {
        _editableGroups = editable;
        _generating     = false;
        _statusMsg      = msg ?? 'Generated ${editable.length} procurement list(s). Review and adjust before sending.';
        _statusIsError  = false;
      });
      _loadLogs();
    } on ApiException catch (e) {
      setState(() { _generating = false; _statusMsg = e.message; _statusIsError = true; });
    } catch (e) {
      setState(() { _generating = false; _statusMsg = e.toString(); _statusIsError = true; });
    }
  }

  /// Build WhatsApp URLs from the (possibly edited) groups, then open them.
  Future<void> _sendGroup(_EditableGroup group) async {
    setState(() => _sending = true);
    try {
      final payload = [group.toPayload()];
      final result = await ApiService.instance.buildProcurementWhatsApp(payload);
      final url = result.isNotEmpty ? result[0]['whatsapp_url'] as String? : null;
      if (url != null) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    for (final g in _editableGroups) g.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.debtRed : AppTheme.paidGreen,
    ));
  }

  /// Phase 8: Add an ad-hoc item to a specific group (or reassign to another group).
  Future<void> _showAdHocDialog(_EditableGroup targetGroup) async {
    final result = await showDialog<_AdHocResult>(
      context: context,
      builder: (_) => _AdHocItemDialog(
        groups: _editableGroups,
        defaultGroup: targetGroup,
      ),
    );
    if (result == null) return;
    setState(() {
      result.group.addAdHocItem(result.name, result.unit, result.qty);
    });
    _snack('Added "${result.name}" to ${result.group.purchaserName}.');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Header ────────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 800;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.shopping_basket_rounded,
                        color: AppTheme.pinTeal, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Procurement Lists',
                              style: TextStyle(
                                  fontSize: isMobile ? 18 : 18,
                                  fontWeight: FontWeight.w700)),
                          Text('Generate "things to buy" lists routed to each manager',
                              style: TextStyle(
                                  fontSize: isMobile ? 11 : 12,
                                  color: AppTheme.pinMuted)),
                        ],
                      ),
                    ),
                    if (!isMobile) ...[
                      IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          onPressed: _loadLogs,
                          tooltip: 'Refresh logs'),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _generating ? null : _generate,
                        icon: _generating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: Text(_generating ? 'Generating…' : 'Generate Lists'),
                        style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.pinTeal),
                      ),
                    ]
                  ]),
                  if (isMobile) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.refresh_rounded),
                            onPressed: _loadLogs,
                            tooltip: 'Refresh logs'),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _generating ? null : _generate,
                          icon: _generating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.auto_awesome_rounded, size: 18),
                          label: Text(_generating ? 'Generating…' : 'Generate Lists'),
                          style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.pinTeal),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        const Divider(height: 1),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Status banner ────────────────────────────────
                if (_statusMsg != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _statusIsError
                          ? AppTheme.debtRed.withOpacity(0.1)
                          : AppTheme.paidGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _statusIsError
                              ? AppTheme.debtRed.withOpacity(0.4)
                              : AppTheme.paidGreen.withOpacity(0.4)),
                    ),
                    child: Text(_statusMsg!,
                        style: TextStyle(
                            color: _statusIsError ? AppTheme.debtRed : AppTheme.paidGreen,
                            fontWeight: FontWeight.w600)),
                  ),

                // ── Generated / editable lists ──────────────────
                if (_editableGroups.isNotEmpty) ...[
                  _SectionLabel(
                      icon: Icons.edit_note_rounded,
                      label: 'Adjust Quantities — then Send via WhatsApp'),
                  const SizedBox(height: 12),
                  ..._editableGroups.map((g) => _EditableProcurementCard(
                        group:      g,
                        allGroups:  _editableGroups,
                        onSend:     _sending ? null : () => _sendGroup(g),
                        onAddAdHoc: () => _showAdHocDialog(g),
                      )),
                  const SizedBox(height: 32),
                ],

                // ── Explainer (when no lists generated yet) ──────
                if (_editableGroups.isEmpty && !_generating) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.pinTeal.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.pinTeal.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.info_outline_rounded,
                              color: AppTheme.pinTeal, size: 20),
                          const SizedBox(width: 8),
                          const Text('How procurement lists work',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.pinTeal)),
                        ]),
                        const SizedBox(height: 10),
                        const Text(
                          '1. Assign a "Default Purchaser" to each inventory item '
                          '(an internal manager account in Suppliers).\n'
                          '2. When items drop below minimum stock, tap "Generate Lists".\n'
                          '3. The system groups items by purchaser and creates a '
                          'WhatsApp message for each manager with their specific list.\n'
                          '4. Tap "Send via WhatsApp" to dispatch the list directly.',
                          style: TextStyle(fontSize: 13, height: 1.6),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],

                // ── Logs history ─────────────────────────────────
                if (_logs.isNotEmpty) ...[
                  _SectionLabel(
                      icon: Icons.history_rounded,
                      label: 'History (last 50 generated lists)'),
                  const SizedBox(height: 12),
                  ..._logs.map((log) => _LogTile(log: log)),
                ],

                if (_logs.isEmpty && !_loadingLogs)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(48),
                      child: Text('No procurement lists generated yet.',
                          style: TextStyle(color: AppTheme.pinMuted)),
                    ),
                  ),

                if (_loadingLogs)
                  const Center(
                      child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator())),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 8 Data Models
// ─────────────────────────────────────────────────────────────────────────────

/// Mutable item row inside an editable procurement group.
class _EditableItem {
  final String name;
  final String unit;
  final double inStock;    // original from backend (0 for ad-hoc)
  final bool   isAdHoc;
  final TextEditingController qtyCtrl;
  /// Client-side only — excluded items are hidden from toPayload() and not sent.
  bool excluded;

  _EditableItem({
    required this.name,
    required this.unit,
    required double initialQty,
    this.inStock  = 0,
    this.isAdHoc  = false,
    this.excluded = false,
  }) : qtyCtrl = TextEditingController(
          text: initialQty.toStringAsFixed(initialQty % 1 == 0 ? 0 : 1));

  double get qty => double.tryParse(qtyCtrl.text) ?? 0;
  void dispose() => qtyCtrl.dispose();
}

/// Mutable group (purchaser + item list).
class _EditableGroup {
  final String purchaserId;
  final String purchaserName;
  final String? purchaserPhone;
  final List<_EditableItem> items;

  _EditableGroup({
    required this.purchaserId,
    required this.purchaserName,
    this.purchaserPhone,
    required this.items,
  });

  factory _EditableGroup.fromMap(Map<String, dynamic> m) {
    final rawItems = (m['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return _EditableGroup(
      purchaserId:   m['purchaser_id']?.toString()    ?? '__unassigned__',
      purchaserName: m['purchaser_name']?.toString()  ?? 'Unassigned',
      purchaserPhone: m['purchaser_phone']?.toString(),
      items: rawItems.map((i) => _EditableItem(
        name:       i['name']?.toString()  ?? '',
        unit:       i['unit']?.toString()  ?? '',
        initialQty: (i['suggested_qty'] as num?)?.toDouble() ?? 0,
        inStock:    (i['in_stock']       as num?)?.toDouble() ?? 0,
      )).toList(),
    );
  }

  void addAdHocItem(String name, String unit, double qty) {
    items.add(_EditableItem(
        name: name, unit: unit, initialQty: qty, isAdHoc: true));
  }

  /// Active items = not excluded and qty > 0.
  List<_EditableItem> get activeItems =>
      items.where((i) => !i.excluded && i.qty > 0).toList();

  int get excludedCount => items.where((i) => i.excluded).length;

  Map<String, dynamic> toPayload() => {
    'purchaser_name':  purchaserName,
    'purchaser_phone': purchaserPhone,
    'items': activeItems
        .map((i) => {'name': i.name, 'unit': i.unit, 'qty': i.qty})
        .toList(),
  };

  void dispose() {
    for (final i in items) i.dispose();
  }
}

class _AdHocResult {
  final _EditableGroup group;
  final String name;
  final String unit;
  final double qty;
  _AdHocResult({required this.group, required this.name,
                required this.unit, required this.qty});
}

// ─────────────────────────────────────────────────────────────────────────────
// Editable Procurement Group Card (Phase 8)
// ─────────────────────────────────────────────────────────────────────────────

class _EditableProcurementCard extends StatefulWidget {
  final _EditableGroup group;
  final List<_EditableGroup> allGroups;
  final VoidCallback? onSend;
  final VoidCallback onAddAdHoc;

  const _EditableProcurementCard({
    required this.group,
    required this.allGroups,
    required this.onSend,
    required this.onAddAdHoc,
  });

  @override
  State<_EditableProcurementCard> createState() => _EditableProcurementCardState();
}

class _EditableProcurementCardState extends State<_EditableProcurementCard> {
  @override
  Widget build(BuildContext context) {
    final group    = widget.group;
    final hasPhone = group.purchaserPhone != null && group.purchaserPhone!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF3E5F5),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  color: Color(0xFF7B1FA2), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.purchaserName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14,
                            color: Color(0xFF4A148C))),
                    if (group.purchaserPhone != null)
                      Text(group.purchaserPhone!,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF7B1FA2))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${group.activeItems.length} item${group.activeItems.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: Color(0xFF4A148C)),
                  ),
                  if (group.excludedCount > 0)
                    Text(
                      '${group.excludedCount} postponed',
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.debtRed),
                    ),
                ],
              ),
            ]),
          ),

          // ── Editable Item Rows ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: group.items.asMap().entries.map((entry) {
                final i      = entry.value;
                final isLast = entry.key == group.items.length - 1;
                final dimColor = Colors.grey.shade400;

                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: i.excluded ? 0.45 : 1.0,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          i.isAdHoc
                              ? Icons.add_circle_outline_rounded
                              : Icons.fiber_manual_record_rounded,
                          size: i.isAdHoc ? 16 : 8,
                          color: i.excluded
                              ? dimColor
                              : i.isAdHoc
                                  ? AppTheme.pinTeal
                                  : AppTheme.pinMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                i.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: i.excluded
                                      ? dimColor
                                      : i.isAdHoc
                                          ? AppTheme.pinTeal
                                          : Colors.black87,
                                  decoration: i.excluded
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: dimColor,
                                ),
                              ),
                              if (!i.isAdHoc && i.inStock > 0)
                                Text(
                                  'In stock: ${i.inStock.toStringAsFixed(i.inStock % 1 == 0 ? 0 : 1)} ${i.unit}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: i.excluded
                                          ? dimColor
                                          : AppTheme.pinMuted),
                                ),
                              if (i.excluded)
                                const Text(
                                  'Postponed — not included in order',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.debtRed,
                                      fontStyle: FontStyle.italic),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Qty field — disabled when excluded
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: i.qtyCtrl,
                            enabled: !i.excluded,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: i.excluded ? dimColor : Colors.black87),
                            decoration: InputDecoration(
                              isDense: true,
                              suffixText: i.unit,
                              suffixStyle: const TextStyle(
                                  fontSize: 11, color: AppTheme.pinMuted),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(
                                    color: AppTheme.pinTeal, width: 2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Exclude / Restore / Delete
                        if (i.isAdHoc && !i.excluded)
                          // Ad-hoc items: hard delete (same as before)
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline_rounded,
                                size: 18, color: AppTheme.debtRed),
                            onPressed: () => setState(() => group.items.remove(i)),
                            tooltip: 'Remove',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          )
                        else if (!i.excluded)
                          // System-suggested items: soft exclude (postpone)
                          IconButton(
                            icon: const Icon(Icons.do_not_disturb_on_outlined,
                                size: 18, color: AppTheme.debtRed),
                            onPressed: () => setState(() => i.excluded = true),
                            tooltip: 'Postpone — remove from this order',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          )
                        else
                          // Restore postponed item
                          IconButton(
                            icon: const Icon(Icons.undo_rounded,
                                size: 18, color: AppTheme.paidGreen),
                            onPressed: () => setState(() => i.excluded = false),
                            tooltip: 'Restore — include in order',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Footer ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              // Add ad-hoc item button
              OutlinedButton.icon(
                onPressed: widget.onAddAdHoc,
                icon: const Icon(Icons.add_rounded, size: 15),
                label: const Text('Add Item', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.pinTeal,
                  side: const BorderSide(color: AppTheme.pinTeal),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
              const Spacer(),
              if (!hasPhone)
                const Text('No phone — WhatsApp unavailable',
                    style: TextStyle(fontSize: 11, color: AppTheme.debtRed))
              else if (group.activeItems.isEmpty)
                const Text('All items postponed — nothing to send',
                    style: TextStyle(fontSize: 11, color: AppTheme.debtRed)),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                // Disable if no active items or no phone
                onPressed: (widget.onSend != null &&
                            hasPhone &&
                            group.activeItems.isNotEmpty)
                    ? widget.onSend
                    : null,
                icon: const Icon(Icons.phone_android_rounded,
                    size: 16, color: Color(0xFF25D366)),
                label: const Text('Send via WhatsApp'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF25D366),
                  side: const BorderSide(color: Color(0xFF25D366)),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── Log Tile ─────────────────────────────────────────────────────────────────

class _LogTile extends StatelessWidget {
  final Map<String, dynamic> log;
  const _LogTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final groups = (log['groups_json'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final generatedAt = log['generated_at'] as String?;
    DateTime? dt;
    try { dt = generatedAt != null ? DateTime.parse(generatedAt).toLocal() : null; } catch (_) {}

    return ExpansionTile(
      leading: const Icon(Icons.receipt_long_rounded, color: AppTheme.pinMuted),
      title: Text(
        dt != null ? _dtFmt.format(dt) : (generatedAt ?? '—'),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${log['item_count']} items · ${groups.length} purchaser group(s)'
        '${log['generated_by'] != null ? ' · by ${log['generated_by']}' : ''}',
        style: const TextStyle(fontSize: 11),
      ),
      children: groups.map((g) {
        final items = (g['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.person_rounded, size: 18, color: Color(0xFF7B1FA2)),
          title: Text(g['purchaser_name']?.toString() ?? 'Unassigned',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text(
            items.map((i) => '${i['name']} (${i['suggested_qty']} ${i['unit']})').join(', '),
            style: const TextStyle(fontSize: 11),
          ),
        );
      }).toList(),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: AppTheme.pinTeal),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.pinTeal)),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 8: Ad-Hoc Item Dialog
// Lets the storekeeper add an item not auto-flagged by the reorder scan.
// ─────────────────────────────────────────────────────────────────────────────

class _AdHocItemDialog extends StatefulWidget {
  final List<_EditableGroup> groups;
  final _EditableGroup defaultGroup;
  const _AdHocItemDialog({required this.groups, required this.defaultGroup});

  @override
  State<_AdHocItemDialog> createState() => _AdHocItemDialogState();
}

class _AdHocItemDialogState extends State<_AdHocItemDialog> {
  final _formKey  = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  final _qtyCtrl  = TextEditingController(text: '1');
  late _EditableGroup _selectedGroup;

  static const _commonUnits = ['kg', 'g', 'L', 'ml', 'pcs', 'dozen', 'bag', 'box', 'bunch'];

  @override
  void initState() {
    super.initState();
    _selectedGroup = widget.defaultGroup;
    _unitCtrl.text = 'pcs';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _unitCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.add_shopping_cart_rounded, color: AppTheme.pinTeal),
        SizedBox(width: 10),
        Text('Add Ad-Hoc Item'),
      ]),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Item name
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Item Name',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              // Unit + Qty in one row
              Row(children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _commonUnits.contains(_unitCtrl.text)
                        ? _unitCtrl.text
                        : null,
                    decoration: const InputDecoration(
                        labelText: 'Unit', isDense: true),
                    items: _commonUnits
                        .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _unitCtrl.text = v);
                    },
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Quantity', isDense: true),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Must be > 0';
                      return null;
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              // Assign to purchaser group
              DropdownButtonFormField<_EditableGroup>(
                value: _selectedGroup,
                decoration: const InputDecoration(
                  labelText: 'Assign to Purchaser',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
                items: widget.groups
                    .map((g) => DropdownMenuItem(
                          value: g,
                          child: Text(g.purchaserName,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (g) {
                  if (g != null) setState(() => _selectedGroup = g);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(_AdHocResult(
              group: _selectedGroup,
              name:  _nameCtrl.text.trim(),
              unit:  _unitCtrl.text.trim(),
              qty:   double.parse(_qtyCtrl.text.trim()),
            ));
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.pinTeal),
          child: const Text('Add to List'),
        ),
      ],
    );
  }
}
