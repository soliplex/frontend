/// Renders [failure] for a log record without echoing the input it was
/// thrown over.
///
/// `FormatException.toString()` embeds roughly 78 characters of
/// `FormatException.source` around the failure offset. Where the source is a
/// persisted blob or a response body, that window is the payload itself, so
/// it must not reach a sink. The offset is a number, and the SDK parsers
/// these callers use (`jsonDecode`, `DateTime.parse`) draw the reason from a
/// fixed vocabulary, so neither carries input. A hand-thrown
/// `FormatException` is free to interpolate one into its message; none of
/// the callers produce those.
///
/// A [TypeError] is kept whole. The runtime builds it from type names alone,
/// so it carries no value, and it is what says a response arrived as a string
/// where an object was expected.
///
/// An [ArgumentError] — including a [RangeError], which extends it — keeps
/// the name of the parameter it rejected. That is the diagnosis: which field
/// was refused. Its `invalidValue` is the data, and its message is written by
/// whoever threw it, so neither is kept.
///
/// Any other failure is reduced to its type: an exception is free to put a
/// value in its message, and the concrete type isn't known at a catch-all
/// call site.
String describeFailure(Object failure) {
  if (failure is TypeError) return 'TypeError: $failure';
  if (failure is ArgumentError) {
    final name = failure.name;
    return name == null
        ? failure.runtimeType.toString()
        : '${failure.runtimeType}: $name';
  }
  if (failure is! FormatException) return failure.runtimeType.toString();
  final offset = failure.offset;
  final where = offset == null ? '' : ' (offset $offset)';
  return 'FormatException: ${failure.message}$where';
}
