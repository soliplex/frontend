class SendError {
  const SendError(this.error, {this.unsentText});
  final Object error;

  /// The message that never went out, encoded as a composer draft — text with
  /// a marker holding each image's place. Restore it through the composer's
  /// `restoreDraft` rather than assigning it as text, or every image the user
  /// attached vanishes without them seeing it go.
  final String? unsentText;
}
