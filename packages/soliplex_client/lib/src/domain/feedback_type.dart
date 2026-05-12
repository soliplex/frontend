/// The type of feedback a user can give on an assistant run.
enum FeedbackType {
  /// Positive feedback.
  thumbsUp,

  /// Negative feedback.
  thumbsDown;

  /// Serializes this value to the string expected by the backend.
  String toJson() => switch (this) {
    .thumbsUp => 'thumbs_up',
    .thumbsDown => 'thumbs_down',
  };
}
