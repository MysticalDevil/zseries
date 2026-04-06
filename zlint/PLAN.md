# zlint 方案文档

## 1. 目标

实现一个面向 **Zig 项目** 的严格代码检查 CLI：`zlint`。

定位：

- 不是编译器
- 不是通用静态分析平台
- 是 **compile-pass 之后** 的工程约束型 linter
- 重点限制：
  - 显式忽略值：`_ = xxx;`
  - `anytype` 滥用
  - `std.mem.doNotOptimizeAway(...)` 及其别名调用

核心原则：

- 仅在项目可编译通过的前提下执行严格规则
- 基于 `std.zig.Ast` 做结构化分析
- 规则可配置
- 输出面向 CLI / CI / 后续编辑器集成

---

## 2. 已定规格

### 2.1 产物形态

- 先做 **CLI**
- 工具名暂定：`zlint`

### 2.2 配置文件

- 文件名：`zlint.toml`

### 2.3 编译前置检查

- 固定先执行：`zig build`
- 若 `zig build` 失败：
  - 不继续做 lint
  - 退出码为 `2`

### 2.4 扫描范围

- 默认扫描仓库内所有 `.zig`
- 支持 `include` / `exclude`
- 默认排除：
  - `.git`
  - `zig-cache`
  - `.zig-cache`
  - `zig-out`

### 2.5 输出格式

- 文本格式
- JSON 格式

### 2.6 严重级别

- 支持：
  - `error`
  - `warning`

### 2.7 忽略方式

- 支持 **行级忽略**
- 支持 **文件级忽略**
- 必须指定明确规则 ID
- 不支持“忽略全部规则”

---

## 3. 非目标

以下内容不进入 MVP：

- 类型系统级推理
- 跨文件符号传播 / 全项目别名解析
- 基于 build graph 的精确引用文件分析
- SARIF 输出
- Language Server / IDE 插件
- 自动修复
- “智能判断 anytype 是否设计合理”的高级语义分析

---

## 4. 技术路线

## 4.1 主路线

使用 **Zig 标准库内置 AST**：

- `std.zig.Ast`
- token / node / source slice 组合完成规则匹配
- 不依赖外部 parser

原因：

- 依赖最少
- 与 Zig 语法同步最紧
- 更适合做 Zig 专用工程工具

## 4.2 辅助路线

可选后续增强：

- `rg` 做大仓库预过滤
- 但 **不作为规则最终判定依据**

## 4.3 不采用的核心路线

- 纯字符串扫描：误报、漏报、上下文能力差
- `ast-grep` 作为核心引擎：不适合作为主实现

---

## 5. 总体执行流程

## 5.1 CLI 主流程

1. 发现仓库根目录
2. 加载 `zlint.toml`
3. 执行 `zig build`
4. 若编译失败，输出 compile check 失败信息并退出
5. 收集扫描文件列表
6. 解析每个 `.zig` 文件为 AST
7. 预处理忽略注释
8. 依次执行规则
9. 聚合诊断结果
10. 按所选格式输出
11. 根据诊断级别决定退出码

## 5.2 退出码

- `0`
  - 无诊断
  - 或仅有 `warning`
- `1`
  - 至少存在一个 `error`
- `2`
  - compile check 失败
- `3`
  - 配置文件错误 / CLI 参数错误 / 内部执行错误

---

## 6. CLI 设计

## 6.1 MVP 命令

```bash
zlint
zlint --format text
zlint --format json
zlint --config zlint.toml
zlint --root .
```

## 6.2 建议参数

```text
--format <text|json>
--config <path>
--root <path>
--no-compile-check
--quiet
```

说明：

- `--no-compile-check` 可以预留，但默认仍启用 compile check
- 如果你想极简，MVP 可以先不暴露这个参数

## 6.3 后续可扩展参数

```text
--rule <rule-id>
--deny <rule-id>
--warn <rule-id>
--files-from <path>
```

这些不进首版实现。

---

## 7. 配置文件设计

## 7.1 配置示例

```toml
version = 1

[scan]
include = ["."]
exclude = [
  ".git",
  "zig-cache",
  ".zig-cache",
  "zig-out",
]

[output]
format = "text"

[rules.discarded-result]
enabled = true
severity = "error"
strict = true
allow_paths = [
  "std.heap.GeneralPurposeAllocator.deinit",
]
allow_names = [
  "deinit",
  "free",
]

[rules.max-anytype-params]
enabled = true
severity = "error"
max = 2

[rules.no-do-not-optimize-away]
enabled = true
severity = "error"
```

## 7.2 配置模型

### 顶层

- `version: u32`
- `scan`
- `output`
- `rules`

### `scan`

- `include: []const []const u8`
- `exclude: []const []const u8`

### `output`

- `format: "text" | "json"`

### 通用规则字段

- `enabled: bool`
- `severity: "error" | "warning"`

### 规则私有字段

#### `discarded-result`

- `strict: bool`
- `allow_paths: []`
- `allow_names: []`

#### `max-anytype-params`

- `max: usize`

---

## 8. 规则设计

## 8.1 `discarded-result`

### 目标

检测显式丢弃值：

```zig
_ = foo();
_ = bar;
_ = some_expr();
```

### 默认行为

- `strict = true` 时：
  - 任意 `_ = xxx;` 都报

### 放宽行为

后续可支持 `strict = false`：

- 只对右侧为 call / 其他特定表达式时报错

### 豁免策略

同时支持：

- `allow_paths`
- `allow_names`

匹配顺序：

1. 先匹配完整路径
2. 再匹配函数名

### 忽略示例

```zig
_ = foo(); // zlint:ignore discarded-result
```

### 诊断文案

- `discarded-result: discarded value via '_ = ...;'`

### 实现思路

需要识别：

- 赋值语句
- 左值为 `_`
- 提取右值表达式
- 若右值为调用：
  - 提取调用目标名称
  - 还原尽可能完整的路径字符串
  - 检查 `allow_paths` / `allow_names`

### 难点

- 从 AST 中把调用目标还原成统一路径表示
- 需要兼容：
  - `foo()`
  - `a.b()`
  - `a.b.c()`
  - 以及一部分更复杂接收者表达式

### MVP 范围

- 支持基础命名和点链路径提取
- 复杂表达式如果无法完整还原路径：
  - 至少仍能命中 `_ = xxx;`
  - 只是可能无法命中白名单路径

---

## 8.2 `max-anytype-params`

### 目标

限制函数参数里 `anytype` 的数量。

### 默认行为

- `max = 2`
- 若单个函数参数列表中 `anytype` 个数大于 `max`，则报错

### 检测范围

- 普通函数
- `pub fn`
- 非 `test` / `test` 块内函数都可检测
- 暂不区分 exported API 与 internal API

### 诊断文案

- `max-anytype-params: function has 3 anytype params, max allowed is 2`

### 实现思路

遍历函数原型节点：

1. 解析参数列表
2. 统计类型为 `anytype` 的参数个数
3. 若超过阈值，发出诊断

### 难点

- 兼容不同函数声明形态
- 兼容参数带修饰的结构

### MVP 范围

- 只根据 AST 里的参数类型字面结构判断
- 不做“是否滥用”的语义分析

---

## 8.3 `no-do-not-optimize-away`

### 目标

禁止使用：

```zig
std.mem.doNotOptimizeAway(x);
```

同时禁止本地单跳别名绕过：

```zig
const mem = std.mem;
mem.doNotOptimizeAway(x);

const dna = std.mem.doNotOptimizeAway;
dna(x);
```

### 默认行为

- 启用即报

### 检测目标

#### 直接命中

- `std.mem.doNotOptimizeAway(...)`

#### 单跳别名命中

- `const mem = std.mem; mem.doNotOptimizeAway(...)`
- `const dna = std.mem.doNotOptimizeAway; dna(...)`

### 诊断文案

- `no-do-not-optimize-away: forbidden call to std.mem.doNotOptimizeAway`

### 实现思路

分两阶段：

#### 阶段 A：建立文件内别名表

只记录本文件顶层或局部的简单 `const` 绑定：

- `name -> std.mem`
- `name -> std.mem.doNotOptimizeAway`

不处理：

- 多跳传播
- 重新赋值
- 跨文件别名
- 条件分支内复杂覆盖

#### 阶段 B：扫描调用表达式

遇到函数调用时：

1. 尝试恢复调用目标
2. 判断是否为：
   - 直接 `std.mem.doNotOptimizeAway`
   - `alias.doNotOptimizeAway` 且 `alias -> std.mem`
   - `alias(...)` 且 `alias -> std.mem.doNotOptimizeAway`

### MVP 边界

- 只做**文件内、本地、单跳别名解析**
- 不做全仓库 name resolution

---

## 9. 忽略注释设计

## 9.1 行级忽略

语法：

```zig
_ = foo(); // zlint:ignore discarded-result
```

规则：

- 只对当前行生效
- 必须带规则 ID
- 一行可扩展支持多个规则 ID，但 MVP 可先只支持一个

## 9.2 文件级忽略

语法：

```zig
// zlint:file-ignore max-anytype-params
```

规则：

- 对当前文件生效
- 必须带规则 ID
- 建议只在文件顶部区域扫描此类指令

## 9.3 解析策略

每个文件在 AST 规则执行前，先对原始源码做一次注释扫描：

产出：

- `line_ignores: HashMap(line_no -> Set(rule_id))`
- `file_ignores: Set(rule_id)`

规则引擎在发出诊断前统一调用：

- `shouldSuppress(rule_id, line_no)`

---

## 10. 输出设计

## 10.1 文本输出

格式：

```text
path/to/file.zig:12:8: discarded-result: discarded value via `_ = ...;`
```

字段：

- path
- line
- column
- rule id
- message

## 10.2 JSON 输出

建议结构：

```json
{
  "ok": false,
  "summary": {
    "files_scanned": 12,
    "diagnostics": 3,
    "errors": 2,
    "warnings": 1
  },
  "diagnostics": [
    {
      "rule_id": "discarded-result",
      "severity": "error",
      "path": "src/main.zig",
      "line": 12,
      "column": 8,
      "message": "discarded value via `_ = ...;`"
    }
  ]
}
```

### 数据模型

#### `Diagnostic`

- `rule_id`
- `severity`
- `path`
- `line`
- `column`
- `message`

#### `Summary`

- `files_scanned`
- `diagnostics`
- `errors`
- `warnings`

---

## 11. 模块划分

建议项目结构：

```text
zlint/
├── build.zig
├── build.zig.zon
├── src/
│   ├── main.zig
│   ├── cli.zig
│   ├── app.zig
│   ├── compile_check.zig
│   ├── fs_walk.zig
│   ├── config.zig
│   ├── source_file.zig
│   ├── ignore_directives.zig
│   ├── diagnostic.zig
│   ├── reporter/
│   │   ├── text.zig
│   │   └── json.zig
│   ├── ast/
│   │   ├── parse.zig
│   │   ├── nav.zig
│   │   ├── names.zig
│   │   └── locations.zig
│   └── rules/
│       ├── mod.zig
│       ├── discarded_result.zig
│       ├── max_anytype_params.zig
│       └── no_do_not_optimize_away.zig
└── tests/
    ├── config_tests.zig
    ├── ignore_tests.zig
    ├── rules_discarded_result.zig
    ├── rules_max_anytype_params.zig
    ├── rules_no_do_not_optimize_away.zig
    └── integration_cli_tests.zig
```

### 各模块职责

#### `main.zig`

- 进程入口
- 处理退出码

#### `cli.zig`

- 解析参数
- 生成运行选项

#### `app.zig`

- 总调度
- 串联 compile check、扫描、解析、规则执行、输出

#### `compile_check.zig`

- 执行 `zig build`
- 采集返回码与 stderr/stdout

#### `fs_walk.zig`

- 扫描 `.zig` 文件
- include/exclude 过滤

#### `config.zig`

- 解析 TOML
- 校验配置合法性
- 提供默认值

#### `source_file.zig`

- 单文件源码载入
- 保存路径、内容、AST、行索引等

#### `ignore_directives.zig`

- 解析 `zlint:ignore` / `zlint:file-ignore`

#### `diagnostic.zig`

- 诊断与摘要结构

#### `ast/parse.zig`

- `std.zig.Ast.parse`
- AST 生命周期管理

#### `ast/nav.zig`

- 常用 AST 遍历帮助函数

#### `ast/names.zig`

- 从 AST 节点提取名字 / 点路径
- 规则共用

#### `ast/locations.zig`

- token / node -> line / column

#### `rules/mod.zig`

- 规则注册与执行入口

---

## 12. 核心数据结构

## 12.1 `RuleId`

```text
discarded-result
max-anytype-params
no-do-not-optimize-away
```

## 12.2 `Severity`

```text
error
warning
```

## 12.3 `RuleContext`

建议包含：

- allocator
- file path
- source text
- parsed ast
- config
- ignore index
- diagnostic sink

## 12.4 `DiagnosticSink`

职责：

- 接收规则发出的诊断
- 在写入前做 suppression 判断
- 聚合统计

这样规则实现本身更干净。

---

## 13. 实现顺序

## 阶段 0：脚手架

目标：

- CLI 能运行
- 能找到仓库
- 能加载配置
- 能执行 `zig build`

交付：

- `zlint`
- `zlint.toml` 默认加载
- compile check 失败时退出码 `2`

## 阶段 1：文件扫描与解析

目标：

- 扫描 `.zig`
- 解析为 AST
- 正确建立 line/column 映射

交付：

- 文件列表
- AST parse 成功
- 可输出 node 定位信息

## 阶段 2：忽略系统

目标：

- 行级 / 文件级忽略跑通

交付：

- `// zlint:ignore ...`
- `// zlint:file-ignore ...`

## 阶段 3：第一条规则

目标：

- 完成 `discarded-result`

交付：

- `_ = xxx;` 命中
- allow path / allow name 生效
- text/json 输出可见

## 阶段 4：第二条规则

目标：

- 完成 `max-anytype-params`

交付：

- 统计函数参数中的 `anytype`
- 超阈值报错

## 阶段 5：第三条规则

目标：

- 完成 `no-do-not-optimize-away`

交付：

- 直接调用命中
- 单跳别名命中

## 阶段 6：工程化打磨

目标：

- 稳定性与可维护性

交付：

- 错误处理
- 配置默认值
- 更好的消息文本
- README 与示例仓库

---

## 14. 测试计划

## 14.1 单元测试

### 配置测试

- 默认值补全
- 缺失字段
- 非法 severity
- 非法 max 值

### 忽略注释测试

- 行级忽略命中
- 文件级忽略命中
- 未知规则 ID
- 多规则情况

### AST 辅助函数测试

- 路径提取
- token -> line/column
- 调用目标名称提取

## 14.2 规则测试

### `discarded-result`

覆盖：

- `_ = foo();`
- `_ = x;`
- `_ = a.b();`
- `_ = a.b.c();`
- allow_names 生效
- allow_paths 生效
- 行级忽略
- 文件级忽略

### `max-anytype-params`

覆盖：

- 0 / 1 / 2 / 3 个 `anytype`
- `pub fn`
- 普通函数
- 不同参数书写方式

### `no-do-not-optimize-away`

覆盖：

- 直接 `std.mem.doNotOptimizeAway(x)`
- `const mem = std.mem; mem.doNotOptimizeAway(x)`
- `const dna = std.mem.doNotOptimizeAway; dna(x)`
- 非目标同名标识符不误报
- 忽略机制生效

## 14.3 集成测试

建议建若干 fixture 项目：

- `fixtures/pass`
- `fixtures/fail_discarded`
- `fixtures/fail_anytype`
- `fixtures/fail_dna`

验证：

- compile check 成功
- compile check 失败
- 文本输出稳定
- JSON 输出可解析
- 退出码符合预期

---

## 15. 风险点与处理

## 15.1 Zig AST API 细节变化

风险：

- Zig master / 不同版本 AST 细节可能有变化

处理：

- 首版锁定一个 Zig 版本开发
- README 明确支持版本范围

## 15.2 TOML 解析依赖

风险：

- Zig 标准库不直接提供成熟 TOML 解析器

处理：

- 方案 A：引入轻量 TOML 库
- 方案 B：首版使用更简单配置格式，再迁移到 TOML

建议：

- 如果已有稳定 Zig TOML 库可接受，则直接依赖
- 否则先评估依赖质量，避免卡在配置解析

## 15.3 别名解析范围过小

风险：

- `no-do-not-optimize-away` 可能被多跳别名绕过

处理：

- 明确文档写清：MVP 仅支持文件内单跳别名
- 后续再考虑增强

## 15.4 白名单路径恢复不完整

风险：

- 复杂表达式上无法完整恢复调用路径

处理：

- 路径恢复失败时回退函数名匹配
- 文档说明完整路径匹配的适用范围

---

## 16. 后续可扩展规则池

这些规则可以作为第二阶段候选：

- `no-pub-anytype`
- `no-mutable-pub-global`
- `no-unreachable-outside-tests`
- `no-catch-unreachable`
- `no-orelse-unreachable`
- `max-fn-params`
- `max-branch-depth`
- `no-useless-anytype`

建议顺序：

1. `no-pub-anytype`
2. `no-catch-unreachable`
3. `no-orelse-unreachable`
4. `no-mutable-pub-global`

---

## 17. 里程碑

## M1：最小可运行

- CLI 可运行
- `zig build` 校验
- 文本输出
- `discarded-result`

## M2：可用于真实项目

- JSON 输出
- `max-anytype-params`
- 行级 / 文件级忽略
- 基础配置系统

## M3：首个可发布版本

- `no-do-not-optimize-away`
- 别名解析
- 完整测试集
- README / 示例配置 / CI 示例

---

## 18. 推荐的首个开发顺序

建议真实编码时按这个顺序：

1. `main.zig`
2. `cli.zig`
3. `config.zig`
4. `compile_check.zig`
5. `fs_walk.zig`
6. `source_file.zig`
7. `diagnostic.zig`
8. `ast/parse.zig`
9. `ast/locations.zig`
10. `ignore_directives.zig`
11. `rules/discarded_result.zig`
12. `reporter/text.zig`
13. `reporter/json.zig`
14. `rules/max_anytype_params.zig`
15. `ast/names.zig`
16. `rules/no_do_not_optimize_away.zig`

原因：

- 这样可以尽快把第一条规则跑通
- 后两条规则都能复用前面的基础设施

---

## 19. 最终建议

第一版不要追求“规则很多”，要追求：

- 流程稳定
- AST 访问层干净
- 诊断模型稳定
- 配置与忽略语义稳定

真正应该先打磨的是这四块：

1. compile check 边界
2. AST 封装层
3. 诊断与 suppression
4. 规则模块接口

只要这四块稳，后面加规则会很快。

