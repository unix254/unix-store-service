import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'screens/pin_login.dart';

void main() {
  runApp(const YunixStoreApp());
}

class YunixStoreApp extends StatelessWidget {
  const YunixStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yunix Store',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const PinLoginScreen(),
    );
  }
}
