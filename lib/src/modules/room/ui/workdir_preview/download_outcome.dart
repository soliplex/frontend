/// Result of a workdir-file download attempt. Distinguishes user-
/// initiated cancellation from real failure so the UI can render the
/// right inline feedback.
enum DownloadOutcome { success, cancelled, failed }
