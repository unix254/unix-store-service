import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../pin_login.dart';
import 'kitchen_requisition.dart';
import 'kitchen_closing_count.dart';
import 'kitchen_opening_count.dart';

/// Hub screen for kitchen role.
/// Routes to Requisition, Closing Count, or Opening Confirmation
/// depending on the staff member's capabilities.
class KitchenHome extends StatelessWidget {
  final Staff staff;
  const KitchenHome({super.key, required this.staff});

  @override
  Widget build(BuildContext context) {
    final canCount = staff.canDoStockCount;

    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────
              Row(
                children: [
                  const Icon(Icons.restaurant_rounded,
                      color: AppTheme.pinTeal, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Kitchen Hub',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w800)),
                        Text('Welcome, ${staff.name}',
                            style: const TextStyle(
                                fontSize: 13, color: AppTheme.pinMuted)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded),
                    color: Colors.grey.shade500,
                    tooltip: 'Log Out',
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (_) => const PinLoginScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ── Menu Cards ────────────────────────────────────
              _HubCard(
                icon: Icons.assignment_rounded,
                color: AppTheme.pinTeal,
                title: 'Stock Requisition',
                subtitle: 'Request items from the store',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => KitchenRequisitionScreen(staff: staff),
                  ),
                ),
              ),

              if (canCount) ...[
                const SizedBox(height: 16),
                _HubCard(
                  icon: Icons.inventory_rounded,
                  color: const Color(0xFF5C6BC0),
                  title: 'Closing Stock Count',
                  subtitle: 'Submit end-of-shift kitchen count',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => KitchenClosingCountScreen(staff: staff),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _HubCard(
                  icon: Icons.wb_sunny_rounded,
                  color: const Color(0xFFF57C00),
                  title: 'Opening Confirmation',
                  subtitle: 'Confirm morning opening stock count',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => KitchenOpeningCountScreen(staff: staff),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HubCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.pinMuted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.pinMuted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
