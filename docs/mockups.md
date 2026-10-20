# Mockup harness

A second entry point that runs prototype screens in the app's own theme, with
none of the app's boot — no log sinks, no auth, no backend.

```bash
flutter run -t lib/main_mockups.dart -d linux   # or -d macos, -d chrome, ...
flutter run -t lib/main_mockups.dart -d linux --dart-define=MOCKUP=Chat
```

The second form opens straight into the named mockup — on launch and after
every hot restart — which is what you want while iterating on one screen.

The index lists every mockup. Opening one shows it under a toolbar with two
knobs from the design-system adoption checklist:

- **Brightness** — flips between the light and dark brand palettes.
- **Viewport** — pins the width to `Fill` or to a `SoliplexBreakpoints` value
  (320 / 600 / 840). The frame overrides `MediaQuery` as well as the box, so
  layouts that read `MediaQuery.sizeOf` and those that use `LayoutBuilder`
  agree.

The theme is lowered from `BrandTheme.soliplex()` by `lowerBrandTheme` — the
same path `Flavor.build` takes for the standard flavor — so what a mockup
renders here is what it would render in the app. `MockupApp` takes a
`BrandTheme` for prototyping on a fork's brand.

## Adding a mockup

1. Put the screen in its own widget under `lib/src/mockups/`. Return the whole
   screen, `Scaffold` included; it may import anything under `lib/src/`.
2. Register it in `lib/src/mockups/mockups.dart`:

   ```dart
   Mockup(
     name: 'Thread list',
     description: 'Grouped by day, unread dot on the left',
     build: (_) => const ThreadListMockup(),
   ),
   ```

Keep `build` a one-line constructor call and the UI in the widget's own
`build` — hot reload then updates the mockup that is already open.

Mockups live under `lib/` so they can reach the app's internal widgets and
assets, but nothing here is exported from the package barrel, and CI drops
`lib/src/mockups/` from the coverage gate. Design-system rules in `CLAUDE.md`
apply to mockups as to any other UI: they are drafts of app code, not
throwaways. `lib/src/mockups/example_mockup.dart` is a starter to copy.

## The chat mockup

`lib/src/mockups/chat/` runs the room screen on a static backend:

| File                 | What it is                                                                                                                                                     |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `chat_screen.dart`   | A **copy** of `lib/src/modules/room/ui/room_screen.dart` with its imports repointed. Edit it freely; the app's screen is untouched.                             |
| `static_backend.dart`| `StaticSoliplexApi` answers every call the chat makes from in-memory maps; `ScriptedAgUiStreamClient` streams a canned reply to a send; anything unstubbed throws, naming the request. |
| `sample_data.dart`   | The rooms, threads, conversations and documents it opens on.                                                                                                   |
| `chat_mockup.dart`   | Hosts the screen under its own `GoRouter` with the app's room routes, so thread and room switching work; other destinations get a placeholder page.            |

The copy is only the screen — the composition layer. The composer, timeline,
message tiles, rail and sidebar are still imported from the app. When a
mockup needs to change one of those, copy that file the same way (into
`chat/`, imports repointed) and switch the import in `chat_screen.dart`.

Sending a message streams a scripted reply and appends the exchange to the
thread's history, so leaving and returning shows it. Creating, renaming and
deleting threads work the same way. A hot restart resets everything to
`sample_data.dart`.

### The thread panel

`lib/src/mockups/chat/thread_panel/` is the first feature prototyped on the
chat mockup: a floating, tabbed panel in the top-right of the chat area for
everything that belongs to the *thread* (the rail, sidebar and header belong
to the room). It collapses to a pill handle.

| File                     | What it is                                                                                           |
| ------------------------ | ---------------------------------------------------------------------------------------------------- |
| `panel_state.dart`       | `ThreadPanelState`, a `ChangeNotifier` holding every stub: databases, skills, context usage, workspace draft. Each "call" is a delayed state flip. |
| `panel_sample_data.dart` | The opening state.                                                                                   |
| `thread_panel.dart`      | The floating shell: tab strip, collapse, the handle.                                                 |
| `context_tab.dart`       | An accordion of three segments — Databases (open by default), Skills, Context usage.                 |
| `workspace_tab.dart`     | A note to colleagues: recipients as stacked avatars, title, content, embedded documents, send.       |

The context ring beside the send button (`context_gauge.dart`,
`context_usage.dart`) is carried over from `feat/server-measured-context` and
reads the same stubbed usage, so connecting a database or loading a skill
moves it. On a viewport wide enough for both, the conversation column and
composer move over to sit beside the open panel; narrower than that, the
panel floats over the column. On the phone layout (below the tablet
breakpoint) it cannot float at all and opens as a modal sheet from the
composer's *Thread panel* button, sharing the same `ThreadPanelState` — which
also holds what is open, scrolled and typed, so it is there again on reopen.

The composer's leading controls are one `+` menu: attach (files, images, a
folder) and *Filter documents*, which is stubbed to a notice until its purpose
(RAG scope, embeds, or both) is settled.

## The datasets mockup

`lib/src/mockups/datasets/` prototypes rooms as presets rather than walled
gardens: a user picks from every dataset they can access, creates their own,
uploads to them, and shares them once tagged. Nothing here is on the wire —
the backend has no dataset entity yet — and every rule the screens apply is a
working assumption to confirm, not a decision.

```sh
flutter run -t lib/main_mockups.dart -d linux --dart-define=MOCKUP=Datasets
```

Add `--dart-define=DATASETS_ROUTE=/datasets/ops/pump-service-manuals` (any of
the routes below) to open straight on a screen.

| Route                              | Screen                                                                 |
| ---------------------------------- | ---------------------------------------------------------------------- |
| `/lobby`, `/lobby?view=datasets`   | Room presets, or the dataset catalog with search and facets.           |
| `/datasets/new`                    | Create a dataset: namespace, name, level, optional tags.               |
| `/datasets/<namespace>/<name>`     | A dataset's files and ingestion. Anyone with access uploads and marks files outdated; the owner shares and deprecates. |
| `/datasets/<namespace>/<name>/upload` | Choose files, scan, review and commit.                              |
| `/room/mock/<room>[/thread/<id>]`  | The chat mockup's room screen, its panel showing the thread's datasets. |

The rules it assumes:

- **Levels.** A room's level is a ceiling the deployer sets. A thread may use
  datasets at or below it; the picker shows the rest locked.
- **Access.** A dataset is listed only when the user is cleared for its level
  *and* is in its audience. Clearance alone is not need-to-know.
- **No enforcement.** Nothing checks classification, so uploads and shares end
  with an attestation and the scan's results are worded as advisory.
- **Fixed after the first message.** A new thread starts from the room's
  defaults and can change them until its first message; after that they are
  fixed, and *New thread with these datasets* is the way out.
- **No deletion.** Uploads can't be undone. A wrong or outdated file is
  marked outdated instead: it stays indexed and searchable, and the mark shows
  in the files table and the thread panel, and to the agent. A whole dataset
  can be deprecated, which hides it from the catalog.
- **One upload per place.** The dataset page's *Upload to dataset* is the only
  way files join a dataset, and its copy sets it apart from attaching a file
  to a thread.

| File                         | What it is                                                                                |
| ---------------------------- | ----------------------------------------------------------------------------------------- |
| `classification_levels.dart` | The marking vocabulary: PUBLIC, INTERNAL, CONFIDENTIAL, RESTRICTED. The only file allowed hex colors. |
| `model.dart`                 | Datasets, files and their ingestion states, tags, principals, room presets.               |
| `store.dart`                 | `DatasetsStore`: the catalog query, access rule, thread trays, simulated ingestion.       |
| `upload_session.dart`        | One upload: staged files, the simulated scan, what committing adds.                       |
| `sample_data.dart`           | The user, about 115 datasets, three room presets and their conversations.                 |
| `ui/`                        | The screens, and the panel section plugged into the chat mockup.                          |

The chat screen takes the datasets through `ThreadDatasetsSeam`
(`chat/thread_panel/panel_section.dart`): it replaces the panel's Databases
segment and adds a summary row above the composer. Without one, the chat
mockup is unchanged.
