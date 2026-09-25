# Refreshing the backend schema snapshots

`packages/soliplex_client/test/schema/agui_feature_schema_drift_test.dart`
checks the frontend's RAG state mirror against the AG-UI feature schemas the
supported backends publish, snapshotted under
`packages/soliplex_client/test/schema/fixtures/agui_feature_schemas/`. There is
one snapshot per supported haiku.rag version: the one `afsoc-rag` deploys (its
`src/ragserver` lock) and the one backend `main` pins.

Refresh a snapshot whenever backend `main` changes its haiku.rag pin or
registers or changes an AG-UI feature, or `afsoc-rag`'s lock resolves a
different haiku.rag. Run the commands below from the repository root. Backend
`main` gives the latest snapshot; the deployed one comes from the backend tag
whose lock resolves the haiku.rag `afsoc-rag` deploys (currently `v0.82`,
haiku.rag 0.84.0):

```sh
(cd <clean backend worktree> && uv sync)
dart run tool/refresh_agui_feature_schemas.dart <clean backend worktree>
```

The script refuses a checkout with uncommitted changes, since the snapshot's
recorded commit would not reflect them. It names the file for the checkout's
haiku.rag version and records the backend commit inside it. When a version
stops being supported, delete its snapshot and update `_supportedSnapshots` in
the drift test. A failing drift test names the field to add to its contract
table: read by the frontend, or unread with the roadmap item that will read
it.
