# zlint 统一方案与路线图

> 本文为 `docs/PLAN.md` 与 `docs/PLAN-P2.md` 的合并版，作为当前唯一主计划文档。

## 1. 文档目标

定义 `zlint` 的统一方向：

- 保留已确定的 MVP 能力与工程约束；
- 引入下一阶段 AI-oriented 规则路线；
- 固化版本策略、架构分层、测试与验收标准；
- 减少重复与冲突，形成单一事实来源（single source of truth）。

---

## 2. 产品定位与范围

`zlint` 是面向 Zig 项目的工程化 linter，不是编译器，也不是通用风格检查器。

### 2.1 核心定位

- 运行在 **build-pass** 之后（build-gated analysis）；
- 优先识别 **AI 生成代码高发失真模式**；
- 关注“能编过但语义可疑/风险高”的问题；
- 基于 `std.zig.Ast` 做结构化分析，不依赖外部 parser。

### 2.2 当前必须支持

- CLI 形态：`zlint`；
- 配置文件：`zlint.toml`；
- 输出：`text`、`json`；
- 抑制：行级 + 文件级，且必须指定规则 ID。

### 2.3 非目标（当前阶段）

- 编译器级类型推断与数据流精度；
- 跨文件精确符号传播与全程序别名解析；
- 自动修复、LSP/IDE 插件；
- 覆盖整个 Zig 生态的通用 best-practice 检查；
- 兼容旧版 Zig 的适配层维护。

---

## 3. 版本策略（统一结论）

采用 **单版本策略**：仅支持 Zig 最新版（current master / next release line）。

### 3.1 执行原则

- AST 访问直接跟随当前 `std.zig.Ast` / `std.zig.Parse`；
- 允许随 Zig AST 变动做同步重构；
- 明确不维护 0.15/0.14/更旧版本兼容层。

### 3.2 影响

- 优势：设计更简单、规则更直接、测试矩阵更小；
- 代价：升级 Zig 后需要快速跟进；
- 处理：AST 访问集中封装，优先修 frontend 再修规则。

---

## 4. 总体流程与退出码

### 4.1 主流程

1. 发现仓库根目录与配置。
2. 执行 `zig build`（默认必选）。
3. build 失败则跳过 lint 并退出。
4. 收集 `.zig` 文件集合（include/exclude）。
5. 解析 AST，建立 span/line/column 映射。
6. 预处理 suppression（行级/文件级）。
7. 执行规则并聚合诊断。
8. 按输出格式渲染结果并返回退出码。

### 4.2 退出码

- `0`：无诊断，或仅有不触发失败条件的诊断；
- `1`：存在触发失败条件的诊断（默认 `error`，可配置 `fail_on_warning`）；
- `2`：build gate 失败；
- `3`：配置错误、CLI 参数错误、内部执行错误。

---

## 5. CLI 与配置

### 5.1 MVP CLI

```bash
zlint
zlint --format text
zlint --format json
zlint --config zlint.toml
zlint --root .
```

### 5.2 当前 CLI

- 已支持：`--format`、`--config`、`--root`、`--quiet`、`--no-compile-check`、`--no-build`；
- 已支持 verbose 分级：
  - `-v`：pipeline / file / rule 级 trace；
  - `-vv`：在 `-v` 基础上追加 AST 遍历级 trace；
- 约束：
  - `-q` 与任意 verbose 级别冲突；
  - `json` 模式接受 `-v/-vv`，但必须忽略，不得污染 JSON 输出；
- 预留：`--rule`、`--deny`、`--warn`、`--files-from`。

### 5.3 `zlint.toml` 核心模型

- 顶层：`version`、`scan`、`output`、`rules`；
- `scan`：`include` / `exclude` / `skip_tests`；
- `output`：`format`（`text|json`）；
- 规则通用字段：`enabled`、`severity`；
- 扩展建议：`fail_on_warning`、`confidence` 默认策略、baseline 路径（后续）。

默认排除目录：`.git`、`zig-cache`、`.zig-cache`、`zig-out`。

默认测试跳过策略：

- `scan.skip_tests = true`；
- 默认跳过测试/示例路径与文件名模式，例如 `tests/`、`test/`、`__tests__/`、`examples/`、`*_test.zig`、`*.test.zig`、`*.spec.zig`、`test.zig`、`tests.zig`；
- 规则层也必须尊重 `skip_tests`，避免仅在文件发现阶段跳过而在节点级重新命中。

---

## 6. 架构分层（统一版）

系统收敛为 5 层：

1. **Build Gate**：构建前置检查与失败短路。
2. **Source Discovery**：文件收集、分类、排除。
3. **AST Frontend**：`std.zig.Ast` 包装、span/token/node 映射。
4. **Rule Engine**：规则注册、遍历调度、诊断发射。
5. **Diagnostics & Reporting**：聚合、抑制、文本/JSON 输出。

### 6.1 模块边界建议

- `build_gate` / `compile_check`
- `source_set` / `fs_walk`
- `ast_frontend`（parse/nav/names/locations/query）
- `rule_engine` + `rules/*`
- `diagnostics` + `reporter/*`
- `ignore_directives`

关键约束：规则层不得散落底层 AST 索引细节。

---

## 7. 诊断模型与抑制机制

### 7.1 诊断模型

必填字段：

- `rule_id`
- `severity`（`error|warning|help`）
- `file`
- `line` / `column` 或 `span`
- `message`

选填字段：

- `confidence`（`high|medium|low`）
- `category`（如 `lifetime`、`allocator`、`ai-smell`）
- `notes[]`
- `help`
- `related_spans[]`

### 7.2 suppression

- 行级：`// zlint:ignore <rule-id>`；
- 文件级：`// zlint:file-ignore <rule-id>`；
- 必须指定规则 ID，不支持“忽略全部”。

规则执行前先解析注释并建立：

- `line_ignores: line -> set(rule_id)`
- `file_ignores: set(rule_id)`

统一通过 `shouldSuppress(rule_id, line)` 判定。

---

## 8. 规则体系与优先级

### 8.1 与源码对齐：当前已注册规则（已切换 snake_case）

当前对外规则 ID 以 `snake_case` 为准，`ZAIxxx` 仅作为历史映射，不再兼容输入。

| 历史编号 | 规则 ID | 说明 | 当前状态 |
| --- | --- | --- | --- |
| `ZAI001` | `discarded_result` | 检测 `_ = xxx;` 丢弃值 | 已实现 |
| `ZAI002` | `max_anytype_params` | 限制函数 `anytype` 参数数量 | 已实现 |
| `ZAI003` | `no_silent_error_handling` | 检测静默 catch 控制流退出与空 switch else | 已实现 |
| `-` | `discard_assignment` | 检测 `_ = value` 形式的无意义赋值语句 | 已实现（默认关闭） |
| `ZAI004` | `catch_unreachable` | 检测 `catch unreachable` / `orelse unreachable` / `.?` | 已实现 |
| `ZAI005` | `defer_return_invalid` | 检测 `defer` 后返回失效资源 | 已实现 |
| `ZAI006` | `unused_allocator` | 检测 allocator 参数传入但未使用 | 已实现 |
| `ZAI007` | `global_allocator_in_lib` | 检测库函数偷用全局 allocator | 已实现 |
| `ZAI008` | `no_do_not_optimize_away` | 禁止 `std.mem.doNotOptimizeAway` | 已实现 |
| `ZAI011` | `duplicated_code` | 检测重复代码块/重复 if-else 分支 | 已实现 |
| `ZAI016` | `no_anytype_io_params` | 禁止 writer/reader 参数或字段使用 `anytype` | 已实现 |

### 8.2 规划中（未实现）

- `ZAI009`（拟 rule_id：`log_print_instead_of_error_handling`）：`log/print` 代替真正错误处理（P1）
- `ZAI010`（拟 rule_id：`suspicious_cast_chain`）：可疑 cast 链（`@ptrCast` / `@alignCast` / `@constCast` / `@bitCast` 组合，P1）
- `ZAI012`（拟 rule_id：`placeholder_impl_in_production`）：placeholder 实现混入正式路径（P2）
- `ZAI013`（拟 rule_id：`overbroad_pub`）：过宽 `pub`（P2）
- `ZAI014`（拟 rule_id：`fake_anytype_generic`）：假泛型 `anytype`（细分 `A/B/C`，P1/P2）
- `ZAI015`（拟 rule_id：`over_wrapped_abstraction`）：过度包装/空壳抽象（P3）

### 8.3 阶段分组建议（按规则 ID）

- **MVP 稳定组**：`discarded_result`、`max_anytype_params`、`no_silent_error_handling`、`no_do_not_optimize_away`
- **AI P0 组**：`catch_unreachable`、`defer_return_invalid`、`unused_allocator`、`global_allocator_in_lib`
- **启发式增强组**：`duplicated_code`、`no_anytype_io_params` + 后续规划规则

规则纳入默认集需满足：

- LLM 高发；或
- build-pass 但语义高风险；且
- 误报控制可接受。

---

## 9. 误报治理与放行策略

### 9.1 原则

- 宁可少抓，不做高误报默认规则；
- 高置信规则先保守，再逐步扩张；
- 每条规则必须定义降级条件与放行条件。
- 已落地：`duplicated_code` 对低风险模板重复降级为 `help`，不再一律作为 `warning`。

### 9.2 常见放行上下文

- `test`、`example/demo`、`benchmark`；
- `main`/入口层；
- generated code；
- 有明确不变量注释的局部代码。

### 9.3 baseline（后续）

- 首次落地记录历史问题；
- CI 仅拦截新增问题；
- 不改变规则语义，只改变门禁策略。

---

## 10. 测试策略

### 10.1 测试层级

- Rule unit corpus：每条规则 `positive_*` / `negative_*` / `edge_*`；
- Integration corpus：多文件、可构建、小型真实片段；
- Regression corpus：误报/漏报修复样本沉淀。

### 10.2 最低覆盖要求

- 每条规则至少 3 组正例 + 3 组反例；
- 高置信规则必须有误报防护样本；
- AST 版本升级后优先跑 corpus 回归。

### 10.3 MVP fixture 建议

- `fixtures/pass`
- `fixtures/fail_discarded`
- `fixtures/fail_anytype`
- `fixtures/fail_dna`
- `fixtures/fail_zai004~zai007`（进入 P2 后补齐）

---

## 11. 里程碑与验收

### M1：基础设施可用（已完成）

- CLI 可运行，build gate 生效；
- AST 建立与 span 输出稳定；
- 可注册并执行空规则集。

### M2：MVP 规则可用（已完成）

- `discarded_result`、`max_anytype_params`、`no_silent_error_handling`、`no_do_not_optimize_away` 可运行；
- text/json 输出稳定；
- suppression 生效。

补充现状：

- `json` 模式失败路径也输出纯 JSON；
- `json` 模式下 verbose 必须静默；
- `text` 模式已支持 `-v/-vv` 两级调试输出。

### M3：AI P0 规则落地（已完成）

- `catch_unreachable`、`defer_return_invalid`、`unused_allocator`、`global_allocator_in_lib` 可运行；
- 每条规则具备正反例 corpus；
- 至少 2 条规则具备降级/放行分支。

### M3.5：启发式质量增强（进行中）

- `duplicated_code` 在真实项目上误报可控，并已支持 `warning/help` 分级；
- 为规划规则（原 `ZAI009`、`ZAI010`）预留统一上下文降级机制；
- diagnostics 中轻量分级已实用化（当前已落地 `help`，`confidence` 仍未完全落地）。

### M4：真实项目试用（进行中）

- 中等规模 Zig 项目可稳定运行；
- 误报率可接受；
- Zig AST 变更有明确跟进流程。

---

## 12. 风险与应对

1. AST 变更风险：封装 AST 访问，集中升级 frontend。
2. TOML 依赖风险：优先评估轻量稳定库，避免配置层阻塞主线。
3. 别名/路径恢复边界：明确只支持文件内单跳，诊断中保持透明。
4. 范围漂移风险：默认规则集仅接纳 AI 高发且高价值规则。

---

## 13. 推荐执行顺序

1. 已完成：固化“仅支持最新版 Zig”。
2. 已完成：`build_gate` + `ast_frontend` + `diagnostics` 基础链路。
3. 已完成：`max_anytype_params`、`discarded_result`、`no_silent_error_handling`、`no_do_not_optimize_away` 稳定可用。
4. 已完成：suppression 与基础 corpus/regression 流程建立。
5. 已完成：`catch_unreachable`、`defer_return_invalid`、`unused_allocator`、`global_allocator_in_lib` 落地。
6. 进行中：继续稳定 `duplicated_code` / `no_anytype_io_params`，再推进规划规则。
7. 进行中：把 `help` 级重复命中持续压缩到“值得人工判断”的最小集合。
8. 持续策略：在误报稳定前，不扩展泛化 style 规则。

---

## 14. 结论

`zlint` 的成功标准不是“规则数量”，而是：

- build-gated 流程稳定；
- AST 封装清晰可维护；
- 诊断与 suppression 语义稳定；
- 在 build-pass 前提下高置信抓住 AI 失真模式。

当这四点达成时，项目会形成明确辨识度：

它是面向 Zig 最新版、专注 AI 代码失真风险的工程化 linter。
