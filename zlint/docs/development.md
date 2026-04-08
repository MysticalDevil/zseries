# zlint Development

This document is the maintainer entrypoint for adding or changing `zlint`
rules.

## Source Of Truth

- Planning and follow-up work live in [`TODO.md`](TODO.md)
- Rule catalog, numbering, and user-facing rule docs live in
  [`RULES.md`](RULES.md)
- `ZAIxxx` numbers are documentation identifiers only
- Config and suppression comments always use canonical `snake_case` rule IDs

## Adding A New Rule

Touch the same set of places every time:

1. Add the implementation in `src/rules/<rule_id>.zig`
2. Register the canonical ID in `src/rule_ids.zig`
3. Add config loading and defaults in `src/config.zig`
4. Register the rule in `src/rules/root.zig`
5. Add or update tests in the rule file and any shared traversal helpers
6. Document the rule in `docs/RULES.md`
7. Update `docs/TODO.md` if numbering or priorities changed
8. Update `README.md` if the implemented rule table changed

If a rule introduces a new traversal pattern, keep the rule-specific logic in
the rule file and only move code into `src/rules/utils.zig` when multiple rules
actually share it.

## Rule Design Constraints

- Keep the full-repo baseline at `0 error / 0 warning`
- Prefer structural detection over text matching
- Avoid widening rule scope just because a syntactic pattern is easy to find
- Narrow false positives in the rule before rewriting business code to satisfy
  the rule
- Respect `scan.skip_tests = true` at both file and node level
- `json` mode must stay pure JSON on success and failure paths
- `-v` and `-vv` are text-mode tracing only

## Verification Workflow

Minimum expected checks for rule work:

```bash
zig fmt src/**/*.zig
zig build test
zig build
./zig-out/bin/zlint --root .. --no-compile-check -f json
```

From the monorepo root, the normal self-lint / repo-lint loop is:

```bash
cd zlint && zig build test && zig build
./zlint/zig-out/bin/zlint --root . --no-compile-check -f json
```

If documentation changed:

```bash
rumdl fmt README.md docs/RULES.md docs/TODO.md docs/development.md
rumdl check README.md docs/RULES.md docs/TODO.md docs/development.md
```

## When To Split A Rule

Split a rule when one file is trying to enforce meaningfully different
behaviors, especially if:

- severities differ
- configuration needs differ
- suppression intent differs
- docs need separate guidance

The `catch_unreachable`, `orelse_unreachable`, and `unwrap_optional` split is
the current model to follow.
