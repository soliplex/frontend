import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// ---------------------------------------------------------------------------
/// DEMO STUB — single source of truth for classification markings.
///
/// Every marking surface in the app reads its marking from the providers in
/// this file. They currently return a **hardcoded** default and do not yet
/// reflect any real per-dataset classification coming from the backend.
///
/// This is deliberately the *only* place the default lives: when the real
/// feature lands, swap the bodies here (constant → backend-derived value)
/// and every banner, badge, footer, and notice updates with no call-site
/// changes.
///
/// ⚠️ Because the marking is fixed, this build must only ever be shown
/// against non-controlled / synthetic data. A hardcoded marking is an
/// authoritative-looking claim, not a real control.
/// ---------------------------------------------------------------------------

/// The fixed marking the demo presents everywhere. Change this one line to
/// re-skin the entire app's markings.
const DatasetMarking kDemoDefaultMarking = DatasetMarking.cui;

/// The app's current effective marking — drives the persistent banners,
/// footer, mobile bar, and pre-access notice.
final effectiveMarkingProvider = Provider<DatasetMarking>(
  (ref) => kDemoDefaultMarking,
);

/// The marking for an individual dataset / room / document, keyed by id.
///
/// DEMO STUB — every id resolves to [kDemoDefaultMarking]. Keyed by id now
/// so call sites already pass the identifier they will need once the
/// backend supplies real per-dataset markings.
final datasetMarkingProvider = Provider.family<DatasetMarking, String>(
  (ref, id) => kDemoDefaultMarking,
);
