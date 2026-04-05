import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/inventory_item.dart';
import '../../services/api.dart';

/// Full-page overlay launched from the Inventory screen.
/// Lets a manager systematically count every item on the shelf,
/// then previews discrepancies and auto-applies adjustments.
class CycleCountScreen extends StatefulWidget {
  const CycleCountScreen({super.key});

  @override
  State<CycleCountScreen> createState() => _CycleCountScreenState();
}

class _CycleCountScreenState extends State<CycleCountScreen> {
  // ── State ─────────────────────────────────────────────────────────────────
  List<InventoryItem> _items = [];
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _errors = {};
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;

  // View phase: 'counting' | 'review' | 'done'
  String _phase = 'counting';
  List<_Discrepancy> _discrepancies = [];
  int _appliedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final items = await ApiService.instance.getInventory();
      for (final item in items) {
        _controllers[item.id] = TextEditingController();
      }
      setState(() { _items = items; _loading = false; });
    } on ApiException catch (e) {
      setState(() { _loadError = e.message; _loading = false; });
    } catch (e) {
      setState(() { _loadError = e.toString(); _loading = false; });
    }
  }

  // ── Compute discrepancies & move to review phase ───────────────────────

  void _proceedToReview() {
    // Validate all fields have valid numbers
    bool hasErrors = false;
    for (final item in _items) {
      final raw = _controllers[item.id]!.text.trim();
      if (raw.isEmpty) {
        // Skip items left blank (no change)
        _errors[item.id] = null;
        continue;
      }
      final parsed = double.tryParse(raw);
      if (parsed == null || parsed < 0) {
        _errors[item.id] = 'Enter a valid number ≥ 0';
        hasErrors = true;
      } else {
        _errors[item.id] = null;
      }
    }
    setState(() {});
    if (hasErrors) return;

    // Build discrepancy list
    final discrepancies = <_Discrepancy>[];
    for (final item in _items) {
      final raw = _controllers[item.id]!.text.trim();
      if (raw.isEmpty) continue;
      final counted = double.parse(raw);
      final system = item.quantityInStock;
      final delta = counted - system;
      if (delta.abs() > 0.0001) {
        discrepancies.add(_Discrepancy(
          item: item,
          systemQty: system,
          countedQty: counted,
          delta: delta,
        ));
      }
    }

    setState(() {
      _discrepancies = discrepancies;
      _phase = 'review';
    });
  }

  // ── Apply adjustments ──────────────────────────────────────────────────

  Future<void> _applyAdjustments() async {
    setState(() { _submitting = true; });
    int applied = 0;
    final errors = <String>[];

    for (final d in _discrepancies) {
      try {
        await ApiService.instance.adjustStock(
          d.item.id,
          d.delta,
          reason: 'Cycle Count',
        );
        applied++;
      } on ApiException catch (e) {
        errors.add('${d.item.name}: ${e.message}');
      } catch (e) {
        errors.add('${d.item.name}: $e');
      }
    }

    setState(() {
      _appliedCount = applied;
      _submitting = false;
      _phase = 'done';
    });

    if (errors.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Some adjustments failed:\n${errors.join('\n')}'),
        backgroundColor: AppTheme.debtRed,
        duration: const Duration(seconds: 6),
      ));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        backgroundColor: AppTheme.sidebar,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const Icon(Icons.fact_check_rounded, size: 20),
            const SizedBox(width: 10),
            const Text('Cycle Count',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 16),
            _PhaseStepper(phase: _phase),
          ],
        ),
        leading: _phase == 'done'
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Cancel and go back',
                onPressed: () {
                  if (_phase == 'review') {
                    setState(() => _phase = 'counting');
                  } else {
                    Navigator.pop(context);
                  }
                },
              ),
        automaticallyImplyLeading: _phase != 'done',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _LoadError(error: _loadError!, onRetry: _loadItems)
              : _phase == 'counting'
                  ? _CountingPhase(
                      items: _items,
                      controllers: _controllers,
                      errors: _errors,
                      onProceed: _proceedToReview,
                    )
                  : _phase == 'review'
                      ? _ReviewPhase(
                          discrepancies: _discrepancies,
                          submitting: _submitting,
                          onBack: () => setState(() => _phase = 'counting'),
                          onConfirm: _applyAdjustments,
                        )
                      : _DonePhase(
                          appliedCount: _appliedCount,
                          total: _discrepancies.length,
                          onDone: () => Navigator.pop(context, true),
                        ),
    );
  }
}

// ── Phase stepper indicator ───────────────────────────────────────────────

class _PhaseStepper extends StatelessWidget {
  final String phase;
  const _PhaseStepper({required this.phase});

  @override
  Widget build(BuildContext context) {
    final phases = [
      ('counting', 'Count Items'),
      ('review',   'Review Discrepancies'),
      ('done',     'Done'),
    ];
    return Row(
      children: phases.asMap().entries.map((e) {
        final idx = e.key;
        final (key, label) = e.value;
        final active   = phase == key;
        final past     = phases.indexWhere((p) => p.$1 == phase) > idx;
        final color    = active ? AppTheme.pinTeal : (past ? AppTheme.paidGreen : Colors.white30);
        return Row(
          children: [
            if (idx > 0)
              Container(width: 24, height: 1, color: Colors.white24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color),
              ),
              child: Text('${idx + 1}. $label',
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
            ),
          ],
        );
      }).toList(),
    );
  }
}

// ── Phase 1: Counting ──────────────────────────────────────────────────────

class _CountingPhase extends StatelessWidget {
  final List<InventoryItem> items;
  final Map<String, TextEditingController> controllers;
  final Map<String, String?> errors;
  final VoidCallback onProceed;

  const _CountingPhase({
    required this.items,
    required this.controllers,
    required this.errors,
    required this.onProceed,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('0.##');
    return Column(
      children: [
        // Instructions banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          color: const Color(0xFFFFF8E1),
          child: Row(
            children: const [
              Icon(Icons.info_outline_rounded, color: Color(0xFFF9A825), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Walk the store and enter the actual quantity you counted for each item. '
                  'Leave a field blank if you did not count that item (it will be skipped).',
                  style: TextStyle(fontSize: 12, color: Color(0xFF5D4037)),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Table header
                _CountTableHeader(),
                const SizedBox(height: 4),
                // Items
                ...items.map((item) => _CountRow(
                      item: item,
                      controller: controllers[item.id]!,
                      error: errors[item.id],
                      fmtQty: fmt.format(item.quantityInStock),
                    )),
              ],
            ),
          ),
        ),

        // Sticky proceed button
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: onProceed,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Review Discrepancies',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.pinTeal),
            ),
          ),
        ),
      ],
    );
  }
}

class _CountTableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF37474F),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: _TH('Item')),
          Expanded(flex: 1, child: _TH('UOM')),
          Expanded(flex: 2, child: _TH('System Qty')),
          Expanded(flex: 2, child: _TH('Counted Qty')),
        ],
      ),
    );
  }
}

class _TH extends StatelessWidget {
  final String text;
  const _TH(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700));
}

class _CountRow extends StatelessWidget {
  final InventoryItem item;
  final TextEditingController controller;
  final String? error;
  final String fmtQty;

  const _CountRow({
    required this.item,
    required this.controller,
    required this.error,
    required this.fmtQty,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: item.needsReorder ? AppTheme.debtRed.withOpacity(0.04) : Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                if (item.needsReorder)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.warning_amber_rounded,
                        size: 14, color: AppTheme.debtRed),
                  ),
                Expanded(
                  child: Text(item.name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(item.unitOfMeasure,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.pinMuted)),
          ),
          Expanded(
            flex: 2,
            child: Text(fmtQty,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF546E7A))),
          ),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 38,
              child: TextFormField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                ],
                decoration: InputDecoration(
                  hintText: 'blank = skip',
                  hintStyle: const TextStyle(fontSize: 11),
                  errorText: error,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Phase 2: Review ────────────────────────────────────────────────────────

class _ReviewPhase extends StatelessWidget {
  final List<_Discrepancy> discrepancies;
  final bool submitting;
  final VoidCallback onBack;
  final VoidCallback onConfirm;

  const _ReviewPhase({
    required this.discrepancies,
    required this.submitting,
    required this.onBack,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('0.###');

    if (discrepancies.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 72, color: AppTheme.paidGreen),
            const SizedBox(height: 16),
            const Text('All items match the system!',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('No adjustments are needed.',
                style: TextStyle(color: AppTheme.pinMuted)),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back to Count'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onConfirm,
              icon: const Icon(Icons.done_all_rounded),
              label: const Text('Finish (no changes)'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.pinTeal),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          color: AppTheme.debtRed.withOpacity(0.07),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppTheme.debtRed, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${discrepancies.length} discrepanc${discrepancies.length == 1 ? 'y' : 'ies'} found. '
                  'Confirming will apply stock adjustments with reason "Cycle Count".',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF5D4037)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Table(
                border: TableBorder.all(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(12)),
                columnWidths: const {
                  0: FlexColumnWidth(2.5),
                  1: FlexColumnWidth(1.0),
                  2: FlexColumnWidth(1.3),
                  3: FlexColumnWidth(1.3),
                  4: FlexColumnWidth(1.3),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xFF37474F)),
                    children: [
                      _RH('Item'),
                      _RH('UOM'),
                      _RH('System Qty'),
                      _RH('Counted Qty'),
                      _RH('Adjustment'),
                    ],
                  ),
                  ...discrepancies.asMap().entries.map((e) {
                    final d = e.value;
                    final isLoss = d.delta < 0;
                    final deltaColor = isLoss ? AppTheme.debtRed : AppTheme.paidGreen;
                    final rowBg = e.key.isEven
                        ? Colors.white
                        : const Color(0xFFFAFAFA);
                    return TableRow(
                      decoration: BoxDecoration(color: rowBg),
                      children: [
                        _RC(d.item.name, bold: true),
                        _RC(d.item.unitOfMeasure, muted: true),
                        _RC(fmt.format(d.systemQty)),
                        _RC(fmt.format(d.countedQty)),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 11),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isLoss
                                    ? Icons.arrow_downward_rounded
                                    : Icons.arrow_upward_rounded,
                                size: 13,
                                color: deltaColor,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                (d.delta >= 0 ? '+' : '') +
                                    fmt.format(d.delta),
                                style: TextStyle(
                                    fontSize: 13,
                                    color: deltaColor,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: submitting ? null : onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back to Count'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: submitting ? null : onConfirm,
                icon: submitting
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded),
                label: Text(submitting
                    ? 'Applying…'
                    : 'Confirm & Apply ${discrepancies.length} Adjustment${discrepancies.length == 1 ? '' : 's'}'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.pinTeal),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _RH(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700)),
    );

Widget _RC(String text, {bool bold = false, bool muted = false}) =>
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              color: muted ? AppTheme.pinMuted : const Color(0xFF263238))),
    );

// ── Phase 3: Done ──────────────────────────────────────────────────────────

class _DonePhase extends StatelessWidget {
  final int appliedCount;
  final int total;
  final VoidCallback onDone;

  const _DonePhase({
    required this.appliedCount,
    required this.total,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.task_alt_rounded,
              size: 80, color: AppTheme.paidGreen),
          const SizedBox(height: 20),
          const Text('Cycle Count Complete!',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
            total == 0
                ? 'No discrepancies — inventory is accurate.'
                : '$appliedCount of $total adjustment${total == 1 ? '' : 's'} applied successfully.',
            style: const TextStyle(
                fontSize: 15, color: AppTheme.pinMuted),
          ),
          const SizedBox(height: 8),
          const Text(
            'All changes have been recorded with reason "Cycle Count".',
            style: TextStyle(fontSize: 12, color: AppTheme.pinMuted),
          ),
          const SizedBox(height: 36),
          FilledButton.icon(
            onPressed: onDone,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Return to Inventory',
                style: TextStyle(fontSize: 15)),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.pinTeal,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14)),
          ),
        ],
      ),
    );
  }
}

// ── Error state ────────────────────────────────────────────────────────────

class _LoadError extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _LoadError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 56, color: AppTheme.debtRed),
          const SizedBox(height: 12),
          Text(error,
              style: const TextStyle(color: AppTheme.debtRed, fontSize: 14)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry')),
        ],
      ),
    );
  }
}

// ── Data class ─────────────────────────────────────────────────────────────

class _Discrepancy {
  final InventoryItem item;
  final double systemQty;
  final double countedQty;
  final double delta;

  const _Discrepancy({
    required this.item,
    required this.systemQty,
    required this.countedQty,
    required this.delta,
  });
}
