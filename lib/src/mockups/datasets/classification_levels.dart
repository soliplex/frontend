// The one file in the mockups allowed hex color literals: a classification
// marking's colors are fixed per deployment, never derived from the brand, so
// this is the flavor-level configuration a deployment would write. Approved as
// an exception to the design-system no-hex rule for the datasets mockup.
import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Level ids, least to most restrictive — the order is the severity.
const levelIds = ['public', 'internal', 'confidential', 'restricted'];

/// Position in [levelIds]; higher is more restrictive.
int levelRank(String id) => levelIds.indexOf(id);

/// Sample sensitivity labels, one color each.
final mockupClassifications = ClassificationTheme(
  defaultId: 'public',
  levels: const [
    ClassificationLevel(
      id: 'public',
      label: 'PUBLIC',
      background: Color(0xFF2E7D32),
      foreground: Color(0xFFFFFFFF),
    ),
    ClassificationLevel(
      id: 'internal',
      label: 'INTERNAL',
      background: Color(0xFF1565C0),
      foreground: Color(0xFFFFFFFF),
      icon: Icons.lock_outline,
    ),
    ClassificationLevel(
      id: 'confidential',
      label: 'CONFIDENTIAL',
      background: Color(0xFFF9A825),
      foreground: Color(0xFF000000),
      icon: Icons.lock,
    ),
    ClassificationLevel(
      id: 'restricted',
      label: 'RESTRICTED',
      background: Color(0xFFC62828),
      foreground: Color(0xFFFFFFFF),
      icon: Icons.lock,
    ),
  ],
);

/// The marking text for [id], for sentences that name a level.
String levelLabel(String id) =>
    mockupClassifications.levels.firstWhere((l) => l.id == id).label;
