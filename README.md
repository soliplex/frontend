# Soliplex Frontend

Flutter frontend for Soliplex -- a modular, multi-platform AI chat application.
Serves as both a runnable app and an importable library.

## Features

- **Authentication** -- Multi-server OIDC login with token refresh and secure
  storage
- **Room Chat** -- Threaded conversations with AI agents, streaming responses,
  execution step visibility, and message feedback
- **Citations** -- Source reference display with PDF chunk visualization for
  RAG-backed responses
- **File Upload** -- Cross-platform file attachment to rooms and threads
- **Document Filtering** -- Narrow RAG retrieval to selected documents
- **Quizzes** -- Interactive question sessions with scoring and feedback
- **Diagnostics** -- HTTP request/response debugging with run-level
  filtering
- **Responsive Layout** -- Adaptive wide/narrow views across mobile, tablet,
  and desktop
- **Multi-platform** -- Android, iOS, macOS, Web, Linux, Windows

## Development

```bash
flutter pub get
flutter run -d chrome --web-port 59001
```

## Testing

```bash
# Run all tests
flutter test --reporter failures-only

# Coverage report (app + all packages)
bash scripts/coverage.sh
```

## Pre-commit Hooks

Pre-commit hooks enforce code quality on every commit:

- **dart format** - Ensures consistent code formatting
- **flutter analyze** - Catches errors, warnings, and lint issues
- **markdownlint-cli2** - Lints markdown files
- **gitleaks** - Prevents committing secrets
- **no-commit-to-branch** - Blocks direct commits to main/master
- **check-merge-conflict** - Detects unresolved merge conflict markers
- **check-toml** - Validates TOML file syntax
- **check-yaml** - Validates YAML file syntax

Install uv (if not already installed):

```bash
# macOS/Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Windows
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

Install pre-commit using uv:

```bash
uv tool install pre-commit
```

Set up hooks for this repository:

```bash
pre-commit install
```

Run pre-commit on all files:

```bash
pre-commit run --all-files
```

## Related

- [Soliplex Backend](https://github.com/soliplex/soliplex)
- [Documentation](https://soliplex.github.io/)
