/// Compile-time configuration for the inactivity-logout feature.
///
/// `warningDuration` is the idle interval before the "stay signed in?"
/// dialog appears. `graceDuration` is the additional interval the dialog
/// stays open before the app performs a local logout. Defaults: 10
/// minutes of inactivity, then a 5-minute grace.
///
/// Pass [InactivityConfig.disabled] (or any zero duration) to opt out;
/// the monitor checks [isEnabled] and never schedules timers when off.
class InactivityConfig {
  const InactivityConfig({
    this.warningDuration = defaultWarningDuration,
    this.graceDuration = defaultGraceDuration,
  });

  static const Duration defaultWarningDuration = Duration(minutes: 10);
  static const Duration defaultGraceDuration = Duration(minutes: 5);

  static const InactivityConfig disabled = InactivityConfig(
    warningDuration: Duration.zero,
    graceDuration: Duration.zero,
  );

  final Duration warningDuration;
  final Duration graceDuration;

  bool get isEnabled =>
      warningDuration > Duration.zero && graceDuration > Duration.zero;
}
