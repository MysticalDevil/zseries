# zlint TODO

## Current Baseline

- Keep the full-repo baseline at `0 error / 0 warning`.
- `help` diagnostics are allowed temporarily, but should be reduced only when signal improves.
- `snake_case` rule IDs remain the only accepted config and suppression format.

## Active Priorities

1. Stabilize the newly split panic-handling rules.
   - Keep `catch_unreachable`, `orelse_unreachable`, and `unwrap_optional` independent.
   - Make sure each rule has clear positive/negative tests.
   - Avoid new repo-wide warnings from common Zig idioms unless the warning is clearly actionable.

2. Continue lowering `duplicated_code` noise.
   - Prefer narrowing the rule before refactoring business code.
   - Preserve `warning` only for clearly risky duplication.
   - Keep low-risk templates, rule skeletons, help text, and callback boilerplate at `help` or below.

3. Expand the planned rule set in numeric order.
   - `ZAI016` `log_print_instead_of_error_handling`
   - `ZAI017` `placeholder_impl_in_production`
   - `ZAI018` `overbroad_pub`
   - `ZAI019` `fake_anytype_generic`
   - `ZAI020` `over_wrapped_abstraction`

## Engine / UX Follow-ups

- Keep `json` mode pure JSON for both success and failure paths.
- Preserve `-v` / `-vv` debug output in text mode only.
- Maintain `scan.skip_tests = true` as the default and make sure new rules respect it at both file and node level.

## Maintenance Rules

- Update this file when rule numbering, default-enabled rules, or planned priorities change.
- Do not reintroduce a second roadmap/spec document alongside this TODO; keep one planning source.
