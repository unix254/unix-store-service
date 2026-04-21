import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../services/api.dart';

/// Price Impact Advisory — dedicated BI Hub screen.
/// Shows cost changes over a configurable period, their POS product linkage,
/// and a per-portion cost-rise calculation, with a WhatsApp send button.
class PriceImpactScreen extends StatefulWidget {
  const PriceImpactScreen({super.key});

  @override
  State<PriceImpactScreen> createState() => _PriceImpactScreenState();
}

class _PriceImpactScreenState extends State<PriceImpactScreen> {
  List<Map<String, dynamic>> _items = [];
  bool  _loading = true;
  String? _error;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiService.instance.getInflationSummary(days: _days);
      if (!mounted) return;
      setState(() { _items = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  double _d(Map<String, dynamic> m, String k) =>
      double.tryParse(m[k]?.toString() ?? '0') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          days: _days,
          loading: _loading,
          onRefresh: _load,
          onDaysChanged: (d) { setState(() => _days = d); _load(); },
          onSendWhatsApp: () => _showWhatsAppDialog(context),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorState(error: _error!, onRetry: _load)
                  : _items.isEmpty
                      ? const _EmptyState()
                      : _ImpactTable(items: _items),
        ),
      ],
    );
  }

  Future<void> _showWhatsAppDialog(BuildContext context) async {
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => _WhatsAppDialog(days: _days),
    );
    // result == null means cancelled; '' means send without phone; non-empty = phone number
    if (!mounted || result == null) return;
    await _doSend(result.trim(), context);
  }

  Future<void> _doSend(String phone, BuildContext context) async {
    try {
      final resp = await ApiService.instance.sendPriceImpact(
        phone: phone.isEmpty ? null : phone,
        days: _days,
      );
      final url = resp['whatsapp_url'] as String?;
      if (url != null && mounted) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          _showSnack('Could not open WhatsApp.', error: true);
        }
      } else if (mounted) {
        _showSnack(resp['info'] as String? ?? 'Nothing to send.');
      }
    } catch (e) {
      if (mounted) _showSnack(e.toString(), error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.debtRed : AppTheme.paidGreen,
    ));
  }
}

// ── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int days;
  final bool loading;
  final VoidCallback onRefresh;
  final void Function(int) onDaysChanged;
  final VoidCallback onSendWhatsApp;

  const _Header({
    required this.days,
    required this.loading,
    required this.onRefresh,
    required this.onDaysChanged,
    required this.onSendWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 800;
          final titleWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Price Impact Advisory',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text(
                'Cost changes linked to POS products via Yield Config. '
                'Review selling prices to protect margins.',
                style: TextStyle(fontSize: 12, color: AppTheme.pinMuted),
              ),
            ],
          );
          
          final actionsWidget = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Days selector
              _DaysChip(selected: days == 7,  label: '7d',  onTap: () => onDaysChanged(7)),
              _DaysChip(selected: days == 30, label: '30d', onTap: () => onDaysChanged(30)),
              _DaysChip(selected: days == 90, label: '90d', onTap: () => onDaysChanged(90)),
              const SizedBox(width: 8),
              // WhatsApp send
              FilledButton.icon(
                onPressed: onSendWhatsApp,
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Send via WhatsApp'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              // Refresh
              OutlinedButton.icon(
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ],
          );

          if (isMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleWidget,
                const SizedBox(height: 12),
                actionsWidget,
              ],
            );
          } else {
            return Row(
              children: [
                Expanded(child: titleWidget),
                const SizedBox(width: 16),
                actionsWidget,
              ],
            );
          }
        },
      ),
    );
  }
}

class _DaysChip extends StatelessWidget {
  final bool selected;
  final String label;
  final VoidCallback onTap;
  const _DaysChip({required this.selected, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primary : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? Colors.white : AppTheme.pinMuted,
          ),
        ),
      ),
    );
  }
}

// ── Impact Table ───────────────────────────────────────────────────────────

class _ImpactTable extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _ImpactTable({required this.items});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) => _ItemCard(item: item)).toList(),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ItemCard({required this.item});

  double _d(String k) => double.tryParse(item[k]?.toString() ?? '0') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final kes = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 2);
    final kes0 = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);
    final dateFmt = DateFormat('d MMM y');

    final name       = item['name']?.toString() ?? '—';
    final uom        = item['unit_of_measure']?.toString() ?? '';
    final oldCost    = _d('old_cost');
    final newCost    = _d('new_cost');
    final changedAt  = item['changed_at'] != null
        ? dateFmt.format(DateTime.parse(item['changed_at'].toString()))
        : '—';
    final weeklyImpact = _d('weekly_impact_kes');
    final isUp       = newCost > oldCost;
    final pctChange  = oldCost > 0 ? ((newCost - oldCost) / oldCost * 100) : 0.0;

    final products = (item['impacted_products'] as List?)
        ?.cast<Map<String, dynamic>>() ?? [];

    final cardBorderColor = isUp
        ? AppTheme.debtRed.withOpacity(0.3)
        : AppTheme.paidGreen.withOpacity(0.3);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Ingredient header row ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isUp
                        ? AppTheme.debtRed.withOpacity(0.1)
                        : AppTheme.paidGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    size: 18,
                    color: isUp ? AppTheme.debtRed : AppTheme.paidGreen,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      Text('Changed $changedAt  •  $uom',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.pinMuted)),
                    ],
                  ),
                ),
                // Cost change pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isUp
                        ? AppTheme.debtRed.withOpacity(0.08)
                        : AppTheme.paidGreen.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isUp ? AppTheme.debtRed : AppTheme.paidGreen,
                        width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(kes0.format(oldCost),
                              style: const TextStyle(
                                  fontSize: 12,
                                  decoration: TextDecoration.lineThrough,
                                  color: AppTheme.pinMuted)),
                          const SizedBox(width: 6),
                          Text('→',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade400)),
                          const SizedBox(width: 6),
                          Text(kes0.format(newCost),
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: isUp
                                      ? AppTheme.debtRed
                                      : AppTheme.paidGreen)),
                        ],
                      ),
                      Text(
                        '${isUp ? '+' : ''}${pctChange.toStringAsFixed(1)}%  •  weekly ${weeklyImpact >= 0 ? '+' : ''}${kes0.format(weeklyImpact)}',
                        style: TextStyle(
                            fontSize: 10,
                            color: isUp ? AppTheme.debtRed : AppTheme.paidGreen),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Impacted POS products sub-table ────────────────────
          if (products.isNotEmpty) ...[
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('IMPACTED MENU ITEMS',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.pinMuted,
                          letterSpacing: 1.0)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 600),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Table(
                          border: TableBorder.all(
                              color: const Color(0xFFEEEEEE),
                              borderRadius: BorderRadius.circular(8)),
                          columnWidths: const {
                            0: FlexColumnWidth(3),   // Product name
                            1: FlexColumnWidth(1.8), // Sell price
                            2: FlexColumnWidth(1.5), // Portions/unit
                            3: FlexColumnWidth(2),   // Cost rise/portion
                          },
                      children: [
                        // Header
                        TableRow(
                          decoration:
                              const BoxDecoration(color: Color(0xFF37474F)),
                          children: [
                            _TH('POS Product'),
                            _TH('Sell Price'),
                            _TH('Portions/Unit'),
                            _TH('Cost Rise/Portion'),
                          ],
                        ),
                        // Data rows
                        ...products.asMap().entries.map((e) {
                          final i = e.key;
                          final p = e.value;
                          final sellPrice = double.tryParse(
                                  p['pos_sell_price']?.toString() ?? '0') ??
                              0;
                          final portions = double.tryParse(
                                  p['portions_per_unit']?.toString() ?? '0') ??
                              0;
                          final costRise = double.tryParse(
                                  p['cost_rise_per_portion']?.toString() ??
                                      '0') ??
                              0;
                          final rowBg =
                              i.isEven ? Colors.white : const Color(0xFFFAFAFA);
                          return TableRow(
                            decoration: BoxDecoration(color: rowBg),
                            children: [
                              _TD(p['pos_product_name']?.toString() ?? '—'),
                              _TD(kes0.format(sellPrice)),
                              _TD(portions.toStringAsFixed(
                                  portions % 1 == 0 ? 0 : 1)),
                              _TDColored(
                                  value: isUp
                                      ? '+${kes.format(costRise)}'
                                      : kes.format(costRise),
                                  color: isUp
                                      ? AppTheme.debtRed
                                      : AppTheme.paidGreen),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                  ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: const [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: AppTheme.pinMuted),
                  SizedBox(width: 6),
                  Text(
                    'No POS products linked via Yield Config — set them up in the Yield Config tab.',
                    style: TextStyle(fontSize: 11, color: AppTheme.pinMuted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Table cell helpers (file-local) ──────────────────────────────────────

Widget _TH(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3)),
    );

Widget _TD(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: Color(0xFF263238))),
    );

Widget _TDColored({required String value, required Color color}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(value,
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w700)),
    );

// ── WhatsApp Dialog ────────────────────────────────────────────────────────

class _WhatsAppDialog extends StatefulWidget {
  final int days;
  const _WhatsAppDialog({required this.days});

  @override
  State<_WhatsAppDialog> createState() => _WhatsAppDialogState();
}

class _WhatsAppDialogState extends State<_WhatsAppDialog> {
  final _phoneCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.send_rounded, color: Color(0xFF25D366), size: 22),
          SizedBox(width: 10),
          Text('Send Analysis via WhatsApp'),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: AppTheme.paidGreen),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This will open WhatsApp with the price-impact report '
                      'pre-filled. Enter a phone number to send directly, '
                      'or leave blank to choose a contact in WhatsApp.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Phone Number (optional)',
                hintText: 'e.g. 254712345678',
                prefixIcon: Icon(Icons.phone_rounded),
                helperText: 'International format, no + or spaces',
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _sending
              ? null
              : () => Navigator.of(context).pop(_phoneCtrl.text.trim()),
          style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366)),
          icon: const Icon(Icons.send_rounded, size: 16),
          label: const Text('Open WhatsApp'),
        ),
      ],
    );
  }
}

// ── Empty / Error states ───────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.trending_flat_rounded, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No cost changes in this period.',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('Try selecting a wider date range.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 56, color: AppTheme.debtRed),
          const SizedBox(height: 12),
          Text(error,
              style: const TextStyle(fontSize: 14, color: AppTheme.debtRed)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
