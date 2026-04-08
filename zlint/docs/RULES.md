# zlint Rules

This document describes the current rule set in `zlint`.

- Canonical rule IDs use `snake_case`.
- `ZAIxxx` is the documentation/catalog number only and is not accepted by config/suppressions.
- Rule config keys are also `snake_case`.

---

## Rule index

| Number | rule_id | Default | Severity (default) | Status |
| --- | --- | --- | --- | --- |
| `ZAI001` | `discarded_result` | on | `error` | implemented |
| `ZAI002` | `max_anytype_params` | on | `error` | implemented |
| `ZAI003` | `no_silent_error_handling` | on | `warning` | implemented |
| `ZAI004` | `discard_assignment` | off | `warning` | implemented (opt-in) |
| `ZAI005` | `catch_unreachable` | on | `error` | implemented |
| `ZAI006` | `orelse_unreachable` | on | `error` | implemented |
| `ZAI007` | `unwrap_optional` | on | `warning` | implemented |
| `ZAI008` | `suspicious_cast_chain` | on | `warning` | implemented |
| `ZAI009` | `defer_return_invalid` | on | `error` | implemented |
| `ZAI010` | `unused_allocator` | on | `error` | implemented |
| `ZAI011` | `global_allocator_in_lib` | on | `error` | implemented |
| `ZAI012` | `no_do_not_optimize_away` | on | `error` | implemented |
| `ZAI013` | `duplicated_code` | on | `warning` | implemented |
| `ZAI014` | `no_anytype_io_params` | on | `error` | implemented |
| `ZAI015` | `no_anyerror_return` | on | `warning` | implemented |

### Planned (not implemented)

| Number | tentative rule_id | Description | Priority |
| --- | --- | --- | --- |
| `ZAI016` | `log_print_instead_of_error_handling` | `log/print` in place of real error handling | P1 |
| `ZAI017` | `placeholder_impl_in_production` | TODO/stub/dummy placeholders in production path | P2 |
| `ZAI018` | `overbroad_pub` | visibility too broad (`pub`) | P2 |
| `ZAI019` | `fake_anytype_generic` | pseudo-generic `anytype` misuse | P1/P2 |
| `ZAI020` | `over_wrapped_abstraction` | empty wrapper/over-abstraction patterns | P3 |

---

## Global config model

Common rule fields:

| Key | Type | Meaning |
| --- | --- | --- |
| `enabled` | `bool` | enable/disable the rule |
| `severity` | `"error" | "warning" | "help"` | default severity for the rule |

All rule sections are under `[rules.<rule_id>]`.

Example:

```toml
[rules.max_anytype_params]
enabled = true
severity = "error"
max = 2
```

---

## Suppression syntax

- Line-level: `// zlint:ignore <rule_id>`
- File-level: `// zlint:file-ignore <rule_id>`
- A known `rule_id` is required.

Example:

```zig
// zlint:file-ignore duplicated_code

const x = try foo(); // zlint:ignore discarded_result
```

---

## Rule details

### `discarded_result`

Flags `_ = <expr>;` style dropped results (except simple identifier discard like `_ = unused_param;`).

Extra options:

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `strict` | `bool` | `true` | strict mode toggle |
| `allow_paths` | `string[]` | `[]` | reserved allowlist |
| `allow_names` | `string[]` | `["deinit", "free"]` | function names that can be safely discarded |

```toml
[rules.discarded_result]
enabled = true
severity = "error"
allow_names = ["deinit", "free", "destroy"]
```

### `max_anytype_params`

Limits the number of `anytype` parameters in a function declaration.

Extra options:

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `max` | `usize` | `2` | max allowed `anytype` params |

```toml
[rules.max_anytype_params]
enabled = true
severity = "error"
max = 2
```

### `no_silent_error_handling`

Detects silent `catch` control-flow exits and empty `switch else` blocks.

Current detection scope:

- `catch {}`
- `catch return` when `return` has no value
- `catch continue`
- `catch break`
- empty `switch else` blocks

Explicit non-goals for the current implementation:

- does not flag `orelse return/continue/break`
- does not flag `catch return <value>`
- does not flag `catch unreachable` or `orelse unreachable`
  - these belong to `catch_unreachable`

```toml
[rules.no_silent_error_handling]
enabled = true
severity = "warning"
```

### `discard_assignment`

Detects suspicious discard-style assignment patterns. This rule is implemented but disabled by default.

```toml
[rules.discard_assignment]
enabled = true
severity = "warning"
```

### `catch_unreachable`

Detects `catch unreachable`.

```toml
[rules.catch_unreachable]
enabled = true
severity = "error"
```

### `orelse_unreachable`

Detects `orelse unreachable`.

```toml
[rules.orelse_unreachable]
enabled = true
severity = "error"
```

### `unwrap_optional`

Detects optional unwrap `.?`.

Notes:

- default severity is `warning`
- respects `scan.skip_tests`

```toml
[rules.unwrap_optional]
enabled = true
severity = "warning"
```

### `suspicious_cast_chain`

Detects suspicious nested pointer-cast builtin chains.

Current detection scope:

- `@ptrCast`
- `@alignCast`
- `@constCast`
- `@bitCast`

Current behavior:

- reports nested chains such as `@bitCast(@ptrCast(x))`
- reports longer mixed chains such as `@bitCast(@ptrCast(@alignCast(x)))`
- does not report standalone single casts
- does not report numeric cast chains such as `@intCast` / `@truncate`
- standalone `@constCast(x)` is not reported
- common opaque-context bridge patterns are downgraded to `help`
  - `@ptrCast(@alignCast(ctx))`
  - `@ptrCast(@constCast(&value))`

```toml
[rules.suspicious_cast_chain]
enabled = true
severity = "warning"
```

### `defer_return_invalid`

Detects returns that directly expose likely-invalid fields after deferred cleanup (such as `.items`, `.slice`, `.buffer`).

```toml
[rules.defer_return_invalid]
enabled = true
severity = "error"
```

### `unused_allocator`

Detects allocator-like parameters that are accepted but not used.

```toml
[rules.unused_allocator]
enabled = true
severity = "error"
```

### `global_allocator_in_lib`

Detects library-side use of global allocator access patterns.

```toml
[rules.global_allocator_in_lib]
enabled = true
severity = "error"
```

### `no_do_not_optimize_away`

Forbids `std.mem.doNotOptimizeAway` usage.

```toml
[rules.no_do_not_optimize_away]
enabled = true
severity = "error"
```

### `duplicated_code`

Detects duplicated code blocks / duplicated if-else branches.

Detection behavior:

- uses structural + token feature similarity (not only exact signatures)
- reports measured similarity in output message (for example `92.4% similarity`)
- high-risk long duplicates stay at `warning`
- template-like / low-risk matches are downgraded to `help`

Extra options:

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `min_lines` | `usize` | `8` | minimum duplicate span lines |
| `min_statements` | `usize` | `4` | minimum duplicate statements |
| `min_tokens` | `usize` | `40` | minimum token count of a candidate block |
| `min_similarity_percent` | `usize` | `96` | similarity threshold (1-100) |
| `min_fuzzy_lines` | `usize` | `20` | minimum block lines required for non-exact similarity matching |
| `max_reports_per_file` | `usize` | `12` | cap duplicated_code reports per file |

```toml
[rules.duplicated_code]
enabled = true
severity = "warning"
min_lines = 8
min_statements = 4
min_tokens = 40
min_similarity_percent = 96
min_fuzzy_lines = 20
max_reports_per_file = 12
```

### `no_anytype_io_params`

Forbids `anytype` for IO-like writer/reader parameters or fields.

Detection scope:

- function parameters named as IO aliases (or inferred by writer/reader-style method usage)
- container fields named as IO aliases

Allowed concrete interface types:

- `std.Io.Writer`
- `std.Io.Reader`
- pointer forms of the above

Extra options:

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `io_param_aliases` | `string[]` | `["writer", "reader", "out_writer", "in_reader", "w", "r"]` | alias list for IO-like params/fields |
| `allow_types` | `string[]` | `[]` | additional allowlisted concrete types |

Notes:

- default severity is `error`
- respects `scan.skip_tests`

```toml
[rules.no_anytype_io_params]
enabled = true
severity = "error"
io_param_aliases = ["writer", "reader", "w", "r"]
allow_types = ["myio.Writer"]
```

### `no_anyerror_return`

Detects explicit `anyerror!T` return types on ordinary function declarations.

Current behavior:

- reports `fn foo() anyerror!T`
- does not report inferred `fn foo() !T`
- does not report function pointer or callback type signatures
- does not report standalone `anyerror` type positions
- respects `scan.skip_tests`

```toml
[rules.no_anyerror_return]
enabled = true
severity = "warning"
```

---

## Runtime / output behavior

### Verbose levels

- `-v`: pipeline/file/rule trace in `text` mode
- `-vv`: adds AST traversal trace in `text` mode
- `-q` cannot be combined with `-v` or `-vv`

### JSON contract

- `-f json` must emit pure JSON only
- `-f json -v` and `-f json -vv` are accepted but verbose output is ignored
- failure output is also JSON, with an `err` object instead of side-channel text

### Test skipping

By default, `scan.skip_tests = true`.

This skips common test/example paths and file names, including:

- `tests/`, `test/`, `__tests__/`
- `examples/`, `example/`
- `*_test.zig`, `*.test.zig`, `*.spec.zig`
- `test.zig`, `tests.zig`

---

## Full example

```toml
version = 1
strict_config = true
strict_exit = false
fail_on_warning = false

[scan]
include = ["."]
exclude = [".git", "zig-cache", ".zig-cache", "zig-out"]
skip_tests = true

[output]
format = "text"

[rules.discarded_result]
enabled = true
severity = "error"
allow_names = ["deinit", "free"]

[rules.max_anytype_params]
enabled = true
max = 2

[rules.unwrap_optional]
enabled = true
severity = "warning"

[rules.no_anytype_io_params]
enabled = true
severity = "error"
io_param_aliases = ["writer", "reader", "w", "r"]
```
