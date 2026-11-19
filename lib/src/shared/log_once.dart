import 'package:flutter/foundation.dart';

/// Hashes of the keys [isFirstOccurrence] has seen. The same failure is met
/// again and again: Flutter's `errorBuilder` is invoked on every rebuild while
/// a failed image is mounted, and a viewer meets its content anew each time it
/// is mounted. Without dedupe a single broken image or invalid JSON block in
/// chat history can flood the log sink. Shared by every caller, so a key that
/// fails in several paths logs once total. Only each key's hash is retained, so
/// a `data:` URI's (potentially multi-megabyte) base64 payload is not held for
/// the process lifetime.
final _seenKeys = <int>{};

/// Records [key] and returns whether this is the first time it is seen in this
/// process, for logging a failure once. Callers that share a key space prefix
/// keys by category (such as `json:`) so unrelated failures cannot collide.
/// Keyed on [key]'s hash, so two keys whose hashes collide are treated as one —
/// an acceptable, rare miss for log dedupe.
bool isFirstOccurrence(String key) => _seenKeys.add(key.hashCode);

/// Forgets every key seen so far, so a test that asserts on a record logged
/// once per key starts from a clean set.
@visibleForTesting
void forgetOccurrences() => _seenKeys.clear();
