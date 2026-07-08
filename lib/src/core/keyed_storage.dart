/// Composite, percent-encoded SharedPreferences keys of the form
/// `<prefix>:<enc(c0)>:<enc(c1)>:…`.
///
/// Every component is percent-encoded, so the `:` delimiter only ever appears
/// between components — a component may itself contain `:` `/` `#`. This makes
/// server-scoped prefix sweeps exact (a portless origin no longer prefix-matches
/// the same host with an explicit port) and is what fixes the composer-draft
/// colon-collision bug. By convention `serverId` is the first component.
String encodeKey(String prefix, List<String> components) =>
    [prefix, ...components.map(Uri.encodeComponent)].join(':');

/// The decoded components of [key] if it belongs to [prefix], else `null`.
List<String>? decodeKey(String prefix, String key) {
  final head = '$prefix:';
  if (!key.startsWith(head)) return null;
  return key
      .substring(head.length)
      .split(':')
      .map(Uri.decodeComponent)
      .toList(growable: false);
}

/// The prefix for a server-scoped `startsWith` sweep, assuming `serverId` is the
/// first component: `'<prefix>:<enc(serverId)>:'`.
String serverKeyPrefix(String prefix, String serverId) =>
    '$prefix:${Uri.encodeComponent(serverId)}:';

/// The `userId` component used to bucket device-local state on a server that
/// requires no sign-in, where there is no user identity. Real identities are
/// `iss#sub` and always contain a `#`, so this `#`-free literal can never collide
/// with one. State in this bucket is device-shared across everyone using that
/// unauthenticated server — there is no identity to isolate it by.
const unauthenticatedStorageUser = 'unauthenticated';

/// The `userId` key component for [userId], substituting [unauthenticatedStorageUser]
/// for a null identity (a signed-out or no-auth server). The single choke point
/// for that substitution, so every key-construction site buckets the same way.
String storageUser(String? userId) => userId ?? unauthenticatedStorageUser;
