import 'package:flutter/material.dart';

extension SymbolicColors on ColorScheme {
  bool get isDarkMode => brightness == .dark;

  Color get info => brightness == .light ? Colors.blue : Colors.blue.shade300;

  Color get warning =>
      brightness == .light ? Colors.orange : Colors.orange.shade300;

  Color get danger => brightness == .light ? Colors.red : Colors.red.shade300;

  Color get success =>
      brightness == .light ? Colors.green : Colors.green.shade300;
}
