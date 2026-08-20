import 'dart:async' show TimeoutException;
import 'dart:io' show InternetAddress;

/// How long the lookup may take before the answer stops being worth waiting
/// for. This runs on the path that returns a connection failure to the user, so
/// the deadline is a delay they feel; a name that resolves answers well inside
/// it.
const _lookupDeadline = Duration(milliseconds: 500);

/// Resolves [host] through the platform resolver, bypassing the HTTP stack.
///
/// Deliberately reports the address *count* and families rather than the
/// addresses themselves: whether the name resolves is the diagnostic signal,
/// and a report a user sends onward should not carry a deployment's internal
/// addressing.
Future<String> describeHostResolution(String host) async {
  try {
    final addresses =
        await InternetAddress.lookup(host).timeout(_lookupDeadline);
    if (addresses.isEmpty) return 'resolved, but to no addresses';
    final families = addresses.map((a) => a.type.name).toSet().toList()..sort();
    return 'resolved to ${addresses.length} address(es) '
        '(${families.join(', ')})';
  } on TimeoutException {
    // Distinct from a refusal: the resolver did not answer either way, which
    // on its own says the lookup is not simply returning NXDOMAIN.
    return 'no answer within ${_lookupDeadline.inMilliseconds}ms';
  } on Object catch (e) {
    return 'lookup failed: ${e.runtimeType}: $e';
  }
}
