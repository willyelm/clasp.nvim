# Contributing

This project uses Conventional Commits to drive automatic version tags (`vX.Y.Z`).

## Options changes

Keep the Setup section of [`README.md`](./README.md) up to date with the
defaults in `lua/clasp/config.lua`.

## Tests

```sh
nvim --headless -u NONE -l tests/close.lua
nvim --headless -u NONE -l tests/pairs.lua
nvim --headless -u NONE -l tests/surround.lua
nvim --headless -u NONE -l tests/highlight.lua
nvim --headless -u NONE -l tests/split.lua
```

## Commit Format

Scope is optional.

```text
type: short summary
type(scope): short summary
```

Examples:

- `feat: add workspace symbol mode`
- `fix: handle deleted files in preview`
- `chore(ci): update action versions`

## Version Bump Rules

- `minor`: at least one `feat` commit since last tag.
- `patch`: default (`fix`, `chore`, `docs`, `refactor`, etc).
- `major`: any breaking change.

Breaking changes are marked with either:

```text
feat!: remove deprecated setup option
fix(api)!: rename open() to show()
```
