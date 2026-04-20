/// The type of feedback a user can give on an assistant run.
enum FeedbackType {
  /// Positive feedback.
  thumbsUp,

  /// Negative feedback.
  thumbsDown;

  /// Serializes this value to the string expected by the backend.
  String toJson() => switch (this) {
    FeedbackType.thumbsUp => 'thumbs_up',
    FeedbackType.thumbsDown => 'thumbs_down',
  };
}
