# Soliplex Frontend

Flutter frontend for Soliplex.

## Development

```bash
flutter pub get
flutter run -d chrome --web-port 59001
```

## Testing

```bash
flutter test
```

## Pre-commit Hooks

Pre-commit hooks enforce code quality on every commit:

- **dart format** - Ensures consistent code formatting
- **flutter analyze** - Catches errors, warnings, and lint issues
- **pymarkdown** - Lints markdown files
- **gitleaks** - Prevents committing secrets
- **no-commit-to-branch** - Blocks direct commits to main/master

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
