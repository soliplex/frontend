# Refreshing the backend schema snapshots

`packages/soliplex_client/test/schema/agui_feature_schema_drift_test.dart`
checks the frontend's RAG state mirror against the AG-UI feature schemas the
supported backends publish, snapshotted under
`packages/soliplex_client/test/schema/fixtures/agui_feature_schemas/`. There is
one snapshot per supported haiku.rag version: the one `afsoc-rag` deploys (its
`src/ragserver` lock) and the one backend `main` pins. When both resolve the
same version, one snapshot serves both.

Refresh a snapshot whenever backend `main` changes its haiku.rag pin or
registers or changes an AG-UI feature, or `afsoc-rag`'s lock resolves a
different haiku.rag. Run the commands below from the repository root. Backend
`main` gives the latest snapshot; the deployed one comes from the backend tag
whose lock resolves the haiku.rag `afsoc-rag` deploys. Each snapshot's
`backend_commit` records the checkout it came from.

```sh
(cd <clean backend worktree> && uv sync)
dart run tool/refresh_agui_feature_schemas.dart <clean backend worktree>
```

The script refuses a checkout with uncommitted changes or untracked files,
since the snapshot's recorded commit would not reflect them. It names the file
for the checkout's haiku.rag version and records the backend commit inside it.
When a version stops being supported, delete its snapshot and update
`_supportedSnapshots` in the drift test. The drift test cannot see which keys
haiku.rag clears at the start of a run, so on each refresh also check that
`begin_invocation` still clears the keys `RagSnapshot`'s run-scoped key list
names.

Each drift test failure names the type and field and says what to change. A
new field goes into `_read` if the frontend reads it, or into `_unread` with
the roadmap item that will read it. A field the frontend reads that changed
type or went missing, or a change to `Citation`'s required fields, means its
reader and its table entry need updating; a table entry no snapshot carries
can be deleted along with its reader.
