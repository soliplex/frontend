import 'package:flutter/material.dart';

extension SymbolicColors on ColorScheme {
  bool get isDarkMode => brightness == Brightness.dark;

  Color get info =>
      brightness == Brightness.light ? Colors.blue : Colors.blue.shade300;

  Color get warning =>
      brightness == Brightness.light ? Colors.orange : Colors.orange.shade300;

  Color get danger =>
      brightness == Brightness.light ? Colors.red : Colors.red.shade300;

  Color get success =>
      brightness == Brightness.light ? Colors.green : Colors.green.shade300;
}
