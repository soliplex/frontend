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
