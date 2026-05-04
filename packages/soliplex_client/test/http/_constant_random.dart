import 'dart:math';

/// Deterministic [Random] that always returns [value] from [nextDouble].
/// Used to drive `ResumePolicy.backoffFor` to a known jitter point in
/// tests. Other [Random] methods aren't called by the production code
/// under test, so they're unimplemented.
class ConstantRandom implements Random {
  ConstantRandom(this.value);

  final double value;

  @override
  double nextDouble() => value;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('ConstantRandom.${invocation.memberName}');
}
