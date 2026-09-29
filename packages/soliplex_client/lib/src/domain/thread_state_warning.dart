/// A reason part of a thread's stored AG-UI state cannot be used as stored.
enum ThreadStateWarning {
  /// A `citations` value that is not a list of chunk ids. Under `rag` with no
  /// `citation_index` it is the pre-0.41 shape (haiku.rag 0.33.0–0.40.1),
  /// which stored whole citations; in a block with one it is malformed. A send
  /// empties it, and the answers it belonged to show no sources.
  legacyCitations,

  /// A saved `document_filter` or database `sources` the selection UI cannot
  /// hydrate: it starts from no document or every database, so a send can
  /// search wider than the thread did.
  scopeUnreadable,

  /// A `STATE_DELTA` could not be fully applied and no snapshot has replaced
  /// the state since, so the state the thread shows and a send carries may be
  /// missing changes its runs made.
  stateIncomplete,
}
