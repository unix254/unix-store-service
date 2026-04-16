import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../../models/supplier.dart';
import '../../models/ledger_entry.dart';
import '../../services/api.dart';

final _kes     = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 2);
final _dateFmt = DateFormat('dd MMM yyyy');

/// Expense Accounts Screen — manager float management.
///
/// Shows only internal supplier accounts (manager floats). Provides:
///   • Current float balance per account
///   • Record Cash-In (bank transfer / float top-up)
///   • Record Expense (ad-hoc or supplier payment from float)
///   • Send Float Statement via WhatsApp
///   • Full ledger history per account
///
/// Gated by [Staff.canManageExpenseAccounts] — Storekeepers never see this.
class ExpenseAccountsScreen extends StatefulWidget {
  final Staff staff;
  const ExpenseAccountsScreen({super.key, required this.staff});

  @override
  State<ExpenseAccountsScreen> createState() => _ExpenseAccountsScreenState();
}

class _ExpenseAccountsScreenState extends State<ExpenseAccountsScreen> {
  List<Supplier> _accounts = [];
  Supplier? _selected;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final all = await ApiService.instance.getSuppliers();
      if (!mounted) return;
      setState(() {
        _accounts = all.where((s) => s.isInternal).toList();
        _selected ??= _accounts.isNotEmpty ? _accounts.first : null;
        _loading  = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.debtRed));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.paidGreen));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final isMobile = constraints.maxWidth < 800;

      if (_loading) {
        return const Center(child: CircularProgressIndicator());
      }

      if (_accounts.isEmpty) {
        return _EmptyState(onRefresh: _load);
      }

      // ── Mobile: stack list → detail ─────────────────────────
      if (isMobile) {
        if (_selected == null) {
          return _AccountList(
            accounts: _accounts,
            selected: _selected,
            onSelect: (s) => setState(() => _selected = s),
            onRefresh: _load,
          );
        }
        return Column(children: [
          Container(
            color: AppTheme.surface,
            padding: const EdgeInsets.only(top: 8, bottom: 8, left: 8),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _selected = null),
              ),
              const SizedBox(width: 8),
              const Text('Back to Accounts',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ]),
          ),
          Expanded(
            child: _AccountDetail(
              key: ValueKey(_selected!.id),
              account: _selected!,
              staff: widget.staff,
              onUpdated: _load,
              onError: _showError,
              onSuccess: _showSuccess,
            ),
          ),
        ]);
      }

      // ── Desktop: sidebar + detail ────────────────────────────
      return Row(children: [
        SizedBox(
          width: 300,
          child: _AccountList(
            accounts: _accounts,
            selected: _selected,
            onSelect: (s) => setState(() => _selected = s),
            onRefresh: _load,
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: _selected == null
              ? const _EmptyDetail()
              : _AccountDetail(
                  key: ValueKey(_selected!.id),
                  account: _selected!,
                  staff: widget.staff,
                  onUpdated: _load,
                  onError: _showError,
                  onSuccess: _showSuccess,
                ),
        ),
      ]);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEFT PANEL — Account List
// ─────────────────────────────────────────────────────────────────────────────

class _AccountList extends StatelessWidget {
  final List<Supplier> accounts;
  final Supplier? selected;
  final void Function(Supplier) onSelect;
  final VoidCallback onRefresh;

  const _AccountList({
    required this.accounts,
    required this.selected,
    required this.onSelect,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_rounded,
                    color: AppTheme.pinTeal, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Expense Accounts',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      Text('Manager float accounts',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.pinMuted)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  onPressed: onRefresh,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          // List
          Expanded(
            child: ListView.separated(
              itemCount: accounts.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 16),
              itemBuilder: (_, i) {
                final a = accounts[i];
                final isSelected = selected?.id == a.id;
                final balance = a.balanceDue;
                final isNegative = balance < 0;
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: AppTheme.pinTeal.withOpacity(0.08),
                  onTap: () => onSelect(a),
                  leading: CircleAvatar(
                    backgroundColor: isSelected
                        ? const Color(0xFF1565C0)
                        : const Color(0xFF1565C0).withOpacity(0.12),
                    child: Text(
                      a.name[0].toUpperCase(),
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF1565C0),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  title: Text(a.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(a.location ?? 'No location',
                      style: const TextStyle(fontSize: 11)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _kes.format(balance.abs()),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isNegative
                              ? AppTheme.debtRed
                              : AppTheme.paidGreen,
                        ),
                      ),
                      Text(
                        isNegative ? 'Overdrawn' : 'Available',
                        style: TextStyle(
                          fontSize: 10,
                          color: isNegative
                              ? AppTheme.debtRed
                              : AppTheme.pinMuted,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RIGHT PANEL — Account Detail
// ─────────────────────────────────────────────────────────────────────────────

class _AccountDetail extends StatefulWidget {
  final Supplier account;
  final Staff staff;
  final VoidCallback onUpdated;
  final void Function(String) onError;
  final void Function(String) onSuccess;

  const _AccountDetail({
    super.key,
    required this.account,
    required this.staff,
    required this.onUpdated,
    required this.onError,
    required this.onSuccess,
  });

  @override
  State<_AccountDetail> createState() => _AccountDetailState();
}

class _AccountDetailState extends State<_AccountDetail> {
  List<LedgerEntry> _entries = [];
  bool _loadingLedger = true;

  @override
  void initState() {
    super.initState();
    _loadLedger();
  }

  Future<void> _loadLedger() async {
    setState(() => _loadingLedger = true);
    try {
      final list =
          await ApiService.instance.getSupplierLedger(widget.account.id);
      if (!mounted) return;
      setState(() {
        _entries       = list;
        _loadingLedger = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingLedger = false);
      widget.onError(e.toString());
    }
  }

  Future<void> _recordCashIn() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _CashInDialog(accountId: widget.account.id, accountName: widget.account.name),
    );
    if (ok == true) {
      await _loadLedger();
      widget.onUpdated();
    }
  }

  Future<void> _recordExpense() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _ExpenseDialog(accountId: widget.account.id, accountName: widget.account.name),
    );
    if (ok == true) {
      await _loadLedger();
      widget.onUpdated();
    }
  }

  Future<void> _sendStatement() async {
    try {
      final result = await ApiService.instance
          .getSupplierStatementWhatsApp(widget.account.id);
      final url = result['whatsapp_url'] as String?;
      if (url != null) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          widget.onError('Could not open WhatsApp');
        }
      }
    } catch (e) {
      widget.onError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final a       = widget.account;
    final balance = a.balanceDue;
    final isNeg   = balance < 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ─────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                // Float balance card
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.account_circle_rounded,
                            size: 20, color: Color(0xFF1565C0)),
                        const SizedBox(width: 8),
                        Text(a.name,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1565C0).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('FLOAT ACCOUNT',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF1565C0),
                                  fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      if (a.location != null) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.location_on_rounded,
                              size: 13, color: AppTheme.pinMuted),
                          const SizedBox(width: 4),
                          Text(a.location!,
                              style: const TextStyle(
                                  color: AppTheme.pinMuted, fontSize: 12)),
                        ]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Balance card
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: isNeg
                        ? AppTheme.debtRed.withOpacity(0.08)
                        : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isNeg
                          ? AppTheme.debtRed.withOpacity(0.3)
                          : AppTheme.paidGreen.withOpacity(0.4),
                    ),
                  ),
                  child: Column(children: [
                    Text(
                      'Float Balance',
                      style: TextStyle(
                          fontSize: 11,
                          color: isNeg
                              ? AppTheme.debtRed
                              : AppTheme.paidGreen,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _kes.format(balance.abs()),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isNeg ? AppTheme.debtRed : AppTheme.paidGreen,
                      ),
                    ),
                    if (isNeg)
                      const Text('OVERDRAWN',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.debtRed,
                              fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),

              // ── Action buttons ────────────────────────────────
              Wrap(spacing: 10, runSpacing: 8, children: [
                ElevatedButton.icon(
                  onPressed: _recordCashIn,
                  icon: const Icon(Icons.account_balance_rounded, size: 18),
                  label: const Text('Record Cash-In'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white),
                ),
                ElevatedButton.icon(
                  onPressed: _recordExpense,
                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                  label: const Text('Record Expense'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF57C00),
                      foregroundColor: Colors.white),
                ),
                OutlinedButton.icon(
                  onPressed: _sendStatement,
                  icon: const Icon(Icons.chat_rounded,
                      size: 18, color: Color(0xFF25D366)),
                  label: const Text('Send Float Statement'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    side: const BorderSide(color: Color(0xFF25D366)),
                  ),
                ),
              ]),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Ledger entries ──────────────────────────────────────
        _LedgerSection(entries: _entries, loading: _loadingLedger),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ledger Section
// ─────────────────────────────────────────────────────────────────────────────

class _LedgerSection extends StatelessWidget {
  final List<LedgerEntry> entries;
  final bool loading;

  const _LedgerSection({required this.entries, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Expanded(
          child: Center(child: CircularProgressIndicator()));
    }
    if (entries.isEmpty) {
      return const Expanded(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_rounded,
                  size: 48, color: AppTheme.pinMuted),
              SizedBox(height: 12),
              Text('No transactions yet',
                  style: TextStyle(color: AppTheme.pinMuted, fontSize: 14)),
              SizedBox(height: 4),
              Text('Record a Cash-In to get started.',
                  style: TextStyle(color: AppTheme.pinMuted, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: entries.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (_, i) => _LedgerRow(entry: entries[i]),
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  final LedgerEntry entry;
  const _LedgerRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    Color typeColor;
    IconData typeIcon;
    String typeLabel;

    if (e.isCashIn) {
      typeColor = const Color(0xFF1565C0);
      typeIcon  = Icons.account_balance_rounded;
      typeLabel = 'Cash-In';
    } else if (e.isSupplierPayment) {
      typeColor = const Color(0xFFF57C00);
      typeIcon  = Icons.swap_horiz_rounded;
      typeLabel = 'Paid to Supplier';
    } else if (e.isPurchase) {
      typeColor = AppTheme.debtRed;
      typeIcon  = Icons.shopping_cart_rounded;
      typeLabel = 'Expense';
    } else if (e.isOtherExpense) {
      typeColor = const Color(0xFF7B1FA2);
      typeIcon  = Icons.receipt_outlined;
      typeLabel = 'Other Expense';
    } else {
      typeColor = AppTheme.paidGreen;
      typeIcon  = Icons.payments_rounded;
      typeLabel = 'Payment';
    }

    final isCredit = e.isCashIn || e.isPayment;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: typeColor.withOpacity(0.12),
          child: Icon(typeIcon, size: 18, color: typeColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(typeLabel,
                      style: TextStyle(
                          fontSize: 10,
                          color: typeColor,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Text(
                  _dateFmt.format(DateTime.parse(e.transactionDate)),
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.pinMuted),
                ),
              ]),
              if (e.description != null && e.description!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(e.description!,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF455A64))),
              ],
              if (e.referenceDoc != null && e.referenceDoc!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Ref: ${e.referenceDoc}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.pinMuted,
                        fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
        Text(
          '${isCredit ? '+' : '-'} ${_kes.format(e.amount)}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isCredit ? const Color(0xFF1565C0) : AppTheme.debtRed,
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog — Record Cash-In
// ─────────────────────────────────────────────────────────────────────────────

class _CashInDialog extends StatefulWidget {
  final String accountId;
  final String accountName;
  const _CashInDialog({required this.accountId, required this.accountName});

  @override
  State<_CashInDialog> createState() => _CashInDialogState();
}

class _CashInDialogState extends State<_CashInDialog> {
  final _formKey    = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _refCtrl    = TextEditingController();
  final _descCtrl   = TextEditingController();
  DateTime _date    = DateTime.now();
  bool _saving      = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      await ApiService.instance.recordCashIn(
        widget.accountId,
        amount:          double.parse(_amountCtrl.text.trim()),
        transactionDate: DateFormat('yyyy-MM-dd').format(_date),
        description:     _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        referenceDoc:    _refCtrl.text.trim().isEmpty  ? null : _refCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() { _error = e.message; _saving = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.account_balance_rounded,
            color: Color(0xFF1565C0), size: 22),
        const SizedBox(width: 8),
        Expanded(
            child: Text('Cash-In for ${widget.accountName}',
                style: const TextStyle(fontSize: 16))),
      ]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Amount
            TextFormField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (KES) *',
                prefixIcon: Icon(Icons.attach_money_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Amount is required';
                if (double.tryParse(v) == null || double.parse(v) <= 0) {
                  return 'Enter a valid positive amount';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),

            // Date
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date *',
                  prefixIcon: Icon(Icons.calendar_today_rounded),
                  border: OutlineInputBorder(),
                ),
                child: Text(_dateFmt.format(_date)),
              ),
            ),
            const SizedBox(height: 14),

            // Bank Ref
            TextFormField(
              controller: _refCtrl,
              decoration: const InputDecoration(
                labelText: 'Bank Ref / Cheque No.',
                prefixIcon: Icon(Icons.numbers_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),

            // Description
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                prefixIcon: Icon(Icons.notes_rounded),
                border: OutlineInputBorder(),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(
                      color: AppTheme.debtRed, fontSize: 13)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_rounded, size: 16),
          label: const Text('Save Cash-In'),
          style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog — Record Expense (SUPPLIER_PAYMENT or PURCHASE from float)
// ─────────────────────────────────────────────────────────────────────────────

class _ExpenseDialog extends StatefulWidget {
  final String accountId;
  final String accountName;
  const _ExpenseDialog({required this.accountId, required this.accountName});

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _formKey    = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _refCtrl    = TextEditingController();
  DateTime _date    = DateTime.now();
  String _type      = 'SUPPLIER_PAYMENT'; // or 'PURCHASE'
  bool _saving      = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      await ApiService.instance.addLedgerEntry(widget.accountId, {
        'transaction_type': _type,
        'amount':           double.parse(_amountCtrl.text.trim()),
        'transaction_date': DateFormat('yyyy-MM-dd').format(_date),
        if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
        if (_refCtrl.text.trim().isNotEmpty)  'reference_doc': _refCtrl.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() { _error = e.message; _saving = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.receipt_long_rounded,
            color: Color(0xFFF57C00), size: 22),
        const SizedBox(width: 8),
        Expanded(
            child: Text('Record Expense — ${widget.accountName}',
                style: const TextStyle(fontSize: 15))),
      ]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Expense type toggle
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Expense Type',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.pinMuted,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (val, label) in [
                  ('SUPPLIER_PAYMENT', '🧾 Paid a Supplier'),
                  ('PURCHASE', '🛒 Ad-Hoc Purchase'),
                  ('OTHER_EXPENSE', '📋 Other Expense'),
                ])
                  ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: _type == val,
                    onSelected: (_) => setState(() => _type = val),
                    selectedColor: const Color(0xFFF57C00).withOpacity(0.2),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Amount
            TextFormField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (KES) *',
                prefixIcon: Icon(Icons.attach_money_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Amount is required';
                if (double.tryParse(v) == null || double.parse(v) <= 0) {
                  return 'Enter a valid positive amount';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),

            // Date
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date *',
                  prefixIcon: Icon(Icons.calendar_today_rounded),
                  border: OutlineInputBorder(),
                ),
                child: Text(_dateFmt.format(_date)),
              ),
            ),
            const SizedBox(height: 14),

            // Description
            TextFormField(
              controller: _descCtrl,
              decoration: InputDecoration(
                labelText: _type == 'SUPPLIER_PAYMENT'
                    ? 'Supplier / Payee'
                    : _type == 'OTHER_EXPENSE'
                        ? 'Expense Description *'
                        : 'Description *',
                prefixIcon: const Icon(Icons.notes_rounded),
                border: const OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Description is required' : null,
            ),
            const SizedBox(height: 14),

            // Reference
            TextFormField(
              controller: _refCtrl,
              decoration: const InputDecoration(
                labelText: 'Reference / Receipt No. (optional)',
                prefixIcon: Icon(Icons.numbers_rounded),
                border: OutlineInputBorder(),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(
                      color: AppTheme.debtRed, fontSize: 13)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_rounded, size: 16),
          label: const Text('Save Expense'),
          style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF57C00)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty states
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.account_balance_wallet_rounded,
              size: 56, color: AppTheme.pinMuted),
          SizedBox(height: 12),
          Text('Select an account',
              style: TextStyle(
                  color: AppTheme.pinMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
        ]),
      );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 64, color: AppTheme.pinMuted),
          const SizedBox(height: 16),
          const Text('No expense accounts configured',
              style: TextStyle(
                  color: AppTheme.pinMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          const Text(
              'Mark a supplier as Internal in the Suppliers screen\nto create a manager float account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.pinMuted, fontSize: 13)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ]),
      );
}
