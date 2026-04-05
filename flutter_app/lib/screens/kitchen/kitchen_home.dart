import 'package:flutter/material.dart';
import '../../models/staff.dart';
import 'kitchen_requisition.dart';

/// Entry point for kitchen role – immediately routes to the requisition screen.
class KitchenHome extends StatelessWidget {
  final Staff staff;
  const KitchenHome({super.key, required this.staff});

  @override
  Widget build(BuildContext context) {
    // Kitchen staff go directly to the requisition workflow.
    return KitchenRequisitionScreen(staff: staff);
  }
}
