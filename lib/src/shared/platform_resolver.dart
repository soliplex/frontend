import 'package:flutter/material.dart';

bool isCupertino(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == .iOS || platform == .macOS;
}
