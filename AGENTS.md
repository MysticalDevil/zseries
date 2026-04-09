# Repository Guidelines

## Project Structure & Module Organization

This repository is a Zig monorepo. Top-level directories such as `zcli/`,
`zlint/`, `zlog/`, `ztoml/`, `ztui/`, `ztmpfile/`, `ztotp/`, `zest/`, and
`zjwt/` are independent packages or tools. Most code lives under each
project's `src/`; tests are usually inline `test` blocks or package-local test
files such as `zjwt/tests/basic.zig`. Shared documentation sits in package
`README.md` files and focused docs folders like `zlint/docs/` and
`ztotp/docs/`. The root-level
[`docs/zig-std-quick-reference.md`](docs/zig-std-quick-reference.md) file is a
guidance/overview document for Zig standard-library orientation, not a
repository policy or source of truth.

## Build, Test, and Development Commands

- `just list-projects`: print the workspace project list used by the root task runner.
- `just check`: run the root Markdown checks plus the main package build/test sweep.
- `just fmt`: format tracked Markdown and Zig sources covered by the root workflow.
- `cd <project> && zig build`: build one package, for example `cd zlint && zig build`.
- `cd <project> && zig build test`: run the smallest relevant package test set.
- `./zlint/zig-out/bin/zlint --root . --no-compile-check -f json`: run the repo linter after building `zlint`.

## Coding Style & Naming Conventions

Use `zig fmt` on touched Zig files. Keep canonical rule and config IDs in
`snake_case` (`no_anyerror_return`, not dashed names). Follow existing Zig
conventions: `CamelCase` for types, `lowerCamelCase` for functions and locals,
and small, explicit modules under `src/`. Markdown should pass `rumdl fmt` and
`rumdl check`.

## Testing Guidelines

Prefer adding or updating targeted package tests before broad refactors. Run
the narrowest meaningful command first, then widen if needed. Examples:
`cd ztoml && zig build test`, `cd zlog && zig build test`. For `zlint` rule
work, also run a repo smoke check with JSON output to preserve the `0 error /
0 warning` baseline.

## Commit & Pull Request Guidelines

Keep commits scoped to one concern and use Conventional Commit prefixes already
present in history: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`. A good
series is smaller, reviewable commits rather than one mixed change. Pull
requests should summarize affected packages, list verification commands run, and
call out behavior or rule-severity changes explicitly.

## Contributor Notes

Do not rewrite business code just to silence `zlint`; narrow false positives in
the rule when that is the real issue. Preserve pure JSON output in `zlint`
`-f json` mode, and keep test-skipping behavior explicit when adding new rules.
