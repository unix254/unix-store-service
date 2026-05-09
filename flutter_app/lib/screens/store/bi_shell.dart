import 'package:flutter/material.dart';
import '../../config/theme.dart';
import 'variance_screen.dart';
import 'yield_config_screen.dart';
import 'price_impact_screen.dart';

/// Business Intelligence (BI) Hub — top-level shell for analytics modules.
///
/// Houses three tabs:
///   1. Variance Dashboard   – daily usage variance vs POS sales
///   2. Yield Config         – ingredient-to-portion mapping
///   3. Price Impact Advisory – cost-change impact on POS sell prices
class BIShell extends StatelessWidget {
  const BIShell({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header + TabBar ──────────────────────────────────────────
          Container(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.bar_chart_rounded,
                          color: AppTheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Business Intelligence',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1A2E),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Variance · Yield Config · Price Impact',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.pinMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const TabBar(
                  isScrollable: true,
                  indicatorColor: AppTheme.primary,
                  indicatorWeight: 3,
                  labelColor: AppTheme.primary,
                  unselectedLabelColor: AppTheme.pinMuted,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.analytics_rounded, size: 16),
                          const SizedBox(width: 6),
                          const Text('Variance Dashboard'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tune_rounded, size: 16),
                          const SizedBox(width: 6),
                          const Text('Yield Config'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.trending_up_rounded, size: 16),
                          const SizedBox(width: 6),
                          const Text('Price Impact Advisory'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Tab content ──────────────────────────────────────────────
          const Expanded(
            child: TabBarView(
              children: [
                VarianceScreen(),
                YieldConfigScreen(),
                PriceImpactScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
