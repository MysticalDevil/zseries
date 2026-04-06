# PLAN.md

## 1. 文档目的

本文档定义这个 **AI-oriented Zig linter** 的下一阶段目标、边界、里程碑与验收标准。

该 linter 的核心定位不是通用风格检查器，而是：

- 只抓 **AI 生成 Zig 代码的高发问题**；
- 只抓 **构建通过以后仍然危险/低质/失真的代码**；
- 只依赖 **Zig 最新版标准库提供的 AST 能力** 做静态分析；
- 不承担旧版 Zig 兼容层职责。

---

## 2. 项目定位

### 2.1 核心目标

构建一个针对 Zig 最新版的、对 AI 代码生成模式敏感的 linter，重点识别以下三类问题：

1. **错误路径伪装为成功路径**
2. **所有权/生命周期看似成立，实际失效**
3. **为了“编译通过”而绕过 Zig 的显式约束**

### 2.2 输入前提

本项目采用 **build-gated analysis** 模式：

- 先构建；
- 仅在构建成功后进入分析；
- 不处理“本来就编不过”的代码；
- 不以兼容旧版 Zig AST/API 为目标。

这意味着本项目应把资源集中在：

- **build-pass but semantically suspicious**
- **build-pass but AI-like**
- **build-pass but high-risk at runtime or maintenance time**

### 2.3 非目标

以下内容不纳入当前阶段目标：

- 不做格式化器替代
- 不做通用 style linter
- 不做“覆盖整个 Zig 生态”的 best-practice checker
- 不做旧版 Zig 兼容
- 不做跨版本 AST 抽象层
- 不做完整类型系统/语义分析器重实现
- 不尝试复刻编译器级别的数据流精度

---

## 3. 版本策略

### 3.1 单版本策略

本项目 **只适配 Zig 最新版（current master / next release line）**。

执行原则：

- 源码直接跟随 Zig 最新 `std.zig.Ast` / `std.zig.Parse` 能力演进
- 规则实现直接面向当前 AST 结构
- 允许在 Zig AST 结构变更时同步重构本项目
- 明确拒绝维护“0.15/0.14/更旧版本兼容层”

### 3.2 版本策略带来的收益

- 设计简单
- 规则表达直接
- AST 访问不需要适配层
- 测试矩阵更小
- 维护成本可控
- 诊断信息可以精确贴合最新版 Zig 语义和惯用法

### 3.3 版本策略带来的代价

- 用户必须使用最新版 Zig
- 每次 Zig AST 结构变化后，本项目需要快速跟进
- 不能承诺历史版本稳定支持

这属于有意为之，不规避。

---

## 4. 分析能力边界

### 4.1 基础能力来源

分析前端基于 Zig 标准库 AST 能力构建，依赖的核心事实是：

- `std.zig.Ast` 表示 Zig 源码 AST，根节点位于 `nodes[0]`；
- `Ast` 持有源码、token、node、extra_data、errors 等解析产物；
- `std.zig.Parse` 负责将 token/源码组织为 AST，并使用 `Allocator` 管理解析阶段内存。  

这些能力使本项目可以在不引入外部 parser 的前提下完成语法树遍历与基于节点/Token 的规则分析。citeturn397505view0turn397505view1

### 4.2 当前能力边界

在“仅基于 std AST”的前提下，当前阶段规则应优先依赖：

- 节点类型
- token 位置
- 局部语法上下文
- 语句块结构
- 简单控制流形态
- 文件级/函数级/作用域级启发式

### 4.3 当前不直接追求的能力

以下能力若没有额外语义层，不应在当前阶段过度承诺：

- 完整类型推断
- 全程序实例化分析
- 精确别名分析
- 编译器同等级生命周期证明
- 跨模块精确引用追踪
- 宏观语义等价判定

这些可以作为未来扩展方向，但不应污染当前里程碑。

---

## 5. allocator 策略（项目约定）

本节是 **本项目自身的实现与运行约定**，不是对 Zig 全局“默认 allocator”机制的泛化描述。

### 5.1 开发/调试模式

linter 自身在调试与测试路径优先使用：

- `std.heap.DebugAllocator`

原因：

- 更适合排查本项目自身的泄漏、双重释放、悬垂引用与错误 cleanup
- 与本项目要抓的“AI 生命周期问题”目标一致
- 能提高规则开发阶段的自校验能力

### 5.2 发布/执行模式

发布构建或强调吞吐的分析执行路径可允许使用：

- `std.heap.page_allocator`

适用场景：

- 单次 CLI 进程型执行
- 进程结束即回收
- 不要求在分析器自身运行时保留 DebugAllocator 级别的检查语义

### 5.3 allocator 使用准则

- 不在规则实现中随意创建多套 allocator 策略
- allocator 决策集中在入口层和 analysis session 层
- AST 解析、诊断收集、规则执行共用清晰的内存边界
- 为 future profiling 预留替换 allocator 的单点

### 5.4 本项目不做的事情

- 不做“根据旧版 Zig 自动切换 allocator API”
- 不做多版本 allocator 封装层
- 不为了兼容性降低实现清晰度

---

## 6. 总体架构目标

下一阶段建议把系统收敛为 5 层：

1. **Build Gate**
2. **Source Discovery**
3. **AST Frontend**
4. **Rule Engine**
5. **Diagnostics & Reporting**

### 6.1 Build Gate

职责：

- 执行或接入一次标准 Zig 构建流程
- 仅在构建成功时进入后续分析
- 记录参与构建/参与分析的目标集
- 为诊断输出保留与构建目标相关的上下文

关键要求：

- 构建失败时不进入规则分析
- 构建失败时只输出“analysis skipped due to failed build”级别信息
- 不把“编不过”的问题冒充成 linter 诊断

### 6.2 Source Discovery

职责：

- 确定本次分析需要覆盖的源文件集合
- 区分业务源码、测试代码、示例代码、生成代码
- 为规则提供文件类型上下文

关键要求：

- 支持按 package/root module 收集
- 支持排除第三方/vendor/generated 文件
- 支持 test-only 降级策略

### 6.3 AST Frontend

职责：

- 为每个 Zig 源文件构建 AST
- 保留 token / node / source / span 映射
- 向上层暴露稳定的内部访问抽象

关键要求：

- 内部包装 `std.zig.Ast`
- 避免规则层直接散落大量底层 AST 索引代码
- 提供统一的 span、父节点、语句块、函数节点、catch/orelse/switch/field access 等查询助手

### 6.4 Rule Engine

职责：

- 组织规则注册、执行、诊断发射
- 按文件/按函数/按节点做遍历
- 支持规则开关、级别、类别、抑制注释

关键要求：

- 规则必须独立命名、独立编号
- 规则实现尽量局部化
- 避免每条规则重复写 AST 遍历模板

### 6.5 Diagnostics & Reporting

职责：

- 统一错误码、级别、位置、说明、建议
- 输出面向 CLI / CI 的稳定格式
- 后续可扩展 JSON/SARIF

关键要求：

- 每条诊断必须有 rule id
- 每条诊断必须有主位置和 message
- 必须支持补充 note / rationale / confidence

---

## 7. 规则规划原则

### 7.1 规则纳入条件

一个规则要进入默认规则集，至少满足以下之一：

#### A. 属于 LLM 高发模式
例如：

- `catch unreachable`
- 形式化传 allocator 但不用
- 假泛型 `anytype`
- cast 链消错误
- placeholder 残留

#### B. 属于 Zig 中“能编过但语义很假”的模式
例如：

- `defer` 后返回失效资源
- exhaustive enum/union 上用 `else`
- 日志替代错误处理
- 随意绕开显式所有权

### 7.2 规则分层

#### Tier 1：高置信度规则

- 默认开启
- 可进入 CI fail
- 误报必须极低

#### Tier 2：中等置信度规则

- 默认 warning
- 适合人工审查

#### Tier 3：启发式规则

- 默认可关闭
- 主要用于抓 AI 痕迹
- 允许一定误报

### 7.3 输出原则

每条规则输出都应包含：

- rule id
- severity
- confidence
- primary span
- summary
- reason
- recommendation

---

## 8. 下一阶段规则路线图

下面给出建议的规则路线，按优先级排序。

---

### 8.1 Phase A：高价值、AST 直接可做

这些规则最适合作为下一阶段主目标。

#### ZAI004 `catch unreachable` / `orelse unreachable` / `.?` 滥用

**目标**

识别通过强制假定“不可能失败/不可能为空”来消除错误路径的写法。

**为什么重要**

- 构建可通过
- 运行时风险高
- 高度符合 AI 为了闭合控制流而偷懒的模式

**检测范围**

- `expr catch unreachable`
- `opt orelse unreachable`
- `expr.?`

**第一阶段策略**

- 优先在 I/O、allocator、env、parse、fs、map lookup 等上下文提高严重级别
- test 代码与明确断言上下文可降级

**优先级**

- P0

---

#### ZAI005 `defer` 后返回失效资源

**目标**

识别“知道要 cleanup，但不理解返回值生命周期”的代码。

**典型问题面**

- `defer list.deinit(...)` 后返回 `list.items`
- `defer map.deinit(...)` 后返回 map 或其派生 view
- 返回局部 owner 派生的 slice/pointer

**为什么重要**

- 极像 AI 写法
- build-pass 但语义高危
- 与 Zig 显式生命周期模型直接冲突

**第一阶段策略**

- 先抓最明确的 owner/view 模式
- 不追求编译器级精度
- 允许只覆盖 `ArrayList`、map、buffer writer 等高频容器

**优先级**

- P0

---

#### ZAI006 allocator 参数传入但未使用

**目标**

识别“表面上看懂 Zig allocator 习惯，实则没建模”的假接口。

**典型问题面**

- 参数命名为 `allocator` / `alloc`
- 参数被 `_ = allocator` 吞掉
- 参数既不参与分配，也不向下传递，也不存储

**为什么重要**

- AI 高发
- 误报低
- 极适合作为高置信规则

**优先级**

- P0

---

#### ZAI007 库/普通函数内偷用全局 allocator

**目标**

识别本应由调用方决定分配策略，却在函数体内部直接绑定 allocator 的写法。

**重点关注**

- `std.heap.page_allocator`
- 本地临时 `DebugAllocator` / 其他 allocator 初始化

**为什么重要**

- 直接破坏 API 边界
- AI 为了“自包含”非常容易这么写
- 与 Zig 显式分配策略相违背

**放行范围**

- `main`
- test
- example/demo
- 明确 app entrypoint 层

**优先级**

- P0

---

#### ZAI008 exhaustive 类型上用 `else` 吞分支

**目标**

识别在可枚举完的 `switch` 上使用 `else`，削弱 Zig 编译期穷尽检查的写法。

**为什么重要**

- AI 常把“兜底”当作保险
- 但在 Zig 里这会损失未来演进时的编译器保护

**实现策略**

- 当前阶段先做保守检测
- 只在明显是 enum literal/tag dispatch 的上下文触发

**优先级**

- P1

---

#### ZAI009 `log/print` 代替真正错误处理

**目标**

识别 `catch` 块中只有打印/记录日志然后吞错的模式。

**为什么重要**

- 这是 AI 补洞常见方式
- “至少有输出”不等于正确处理
- 在库代码中尤其不合理

**优先级**

- P1

---

### 8.2 Phase B：生命周期/结构启发式增强

#### ZAI010 可疑 cast 链

**目标**

识别 `@ptrCast` / `@alignCast` / `@constCast` / `@bitCast` 的组合式绕过。

**为什么重要**

- 是 AI 为了消编译器报错的常用手法
- 很适合做“高风险启发式”规则

**优先级**

- P1

---

#### ZAI011 重复分支 / 模板拼接残留

**目标**

识别 if/switch 分支体高度重复、像复制粘贴后没改完的代码。

**为什么重要**

- 非常像 LLM 结构复制
- 常隐藏真实逻辑缺失

**优先级**

- P2

---

#### ZAI012 placeholder 实现混入正式路径

**目标**

识别 `TODO` / `temporary` / `stub` / `dummy` 等临时实现实际出现在正式逻辑路径中。

**为什么重要**

- AI 常用占位逻辑补洞
- 会形成“能编过但业务是假”的结果

**优先级**

- P2

---

#### ZAI013 过宽 `pub`

**目标**

识别为了避免可见性问题而把大量符号直接 `pub` 的倾向。

**为什么重要**

- 很像 AI 代码
- 污染模块边界

**优先级**

- P2

---

### 8.3 Phase C：更强的 AI 痕迹规则

#### ZAI014 假泛型 `anytype`

你已经覆盖“滥用 `anytype`”，下一阶段建议细化为多个子类：

- **ZAI014A**：单参数 `anytype` 且函数体不依赖泛型能力
- **ZAI014B**：函数体只接受一种用法模式，但仍对外暴露 `anytype`
- **ZAI014C**：为了避开明确类型建模而使用 `anytype`

**目标**

把“`anytype` 滥用”从简单语法模式升级为更细的诊断类别。

**优先级**

- P1/P2 混合

---

#### ZAI015 过度包装/空壳抽象

**目标**

识别只有一层转发、没有语义增益的“架构壳”。

**为什么重要**

- AI 很喜欢写“看起来有结构”的薄层
- 可维护性差，信噪比低

**优先级**

- P3

---

## 9. 规则实现顺序

建议按如下顺序推进：

### Milestone 1：打基础

- 建立统一 AST frontend 封装
- 建立 span / token / node 辅助 API
- 建立 rule registry
- 建立 diagnostic schema
- 建立 test corpus 目录结构

### Milestone 2：首批高置信规则

- ZAI004
- ZAI005
- ZAI006
- ZAI007

### Milestone 3：控制流与结构规则

- ZAI008
- ZAI009
- ZAI010

### Milestone 4：AI 痕迹增强

- ZAI011
- ZAI012
- ZAI013
- 拆分 `anytype` 规则族

### Milestone 5：输出与工程化

- JSON 输出
- CI 集成
- rule config
- suppression 机制
- baseline 模式

---

## 10. 内部模块规划

虽然本阶段不写实现代码，但模块边界应先固定。

### 10.1 `build_gate`

职责：

- 构建是否成功
- 目标信息采集
- 分析前置条件判断

### 10.2 `source_set`

职责：

- 文件枚举
- 文件分类
- 排除策略

### 10.3 `ast_frontend`

职责：

- AST 解析
- 节点定位
- source span 映射
- token helpers

### 10.4 `ast_query`

职责：

- 对 AST 查询做更高层封装
- 提供“是否在 catch 内”“是否在 test 中”“父节点链”“返回语句所在函数”等实用查询

### 10.5 `rule_engine`

职责：

- 注册规则
- 执行顺序
- 规则上下文分发
- 诊断汇总

### 10.6 `rules/*`

职责：

- 一条规则一个文件或一个子模块
- 规则逻辑与公共工具分离

### 10.7 `diagnostics`

职责：

- severity/confidence/category
- message builder
- notes/help text
- CLI rendering

### 10.8 `tests/corpus`

职责：

- 正例
- 反例
- 边界样本
- 回归样本

---

## 11. 诊断模型

建议固定如下结构：

### 11.1 必填字段

- `rule_id`
- `severity`
- `confidence`
- `file`
- `span`
- `message`

### 11.2 选填字段

- `notes[]`
- `help`
- `category`
- `tags[]`
- `related_spans[]`

### 11.3 severity 建议

- `error`
- `warning`
- `hint`

### 11.4 confidence 建议

- `high`
- `medium`
- `low`

### 11.5 category 建议

- `error-handling`
- `lifetime`
- `allocator`
- `genericity`
- `api-boundary`
- `ai-smell`
- `maintainability`

---

## 12. 误报控制策略

这是下一阶段必须提前规划的部分。

### 12.1 误报控制总原则

- 宁可少抓，也不要默认规则高误报
- 高置信规则必须先保守再扩张
- 每条规则都必须有“降级条件”和“放行条件”

### 12.2 常见放行上下文

默认应考虑放行或降级：

- test
- example/demo
- benchmark
- 明确带有 `panic path` / `unreachable by invariant` 注释的局部代码
- 入口层 `main`
- generated code

### 12.3 suppression 机制

必须规划最小抑制机制：

- 单行 suppression
- 单规则 suppression
- 文件级 suppression

要求：

- suppression 文法简单
- 诊断中可提示“可用 suppression，但不推荐”
- suppression 不影响其他规则

### 12.4 baseline 模式

为大型已有项目预留 baseline 模式：

- 首次引入 linter 时记录当前已有问题
- 后续 CI 只拦截新增问题

---

## 13. 测试策略

### 13.1 测试目标

- 验证规则命中
- 验证误报控制
- 验证 span 精度
- 验证输出稳定性
- 验证 Zig AST 变动后回归

### 13.2 测试分层

#### A. Rule unit corpus

每条规则至少具备：

- `positive_*`
- `negative_*`
- `edge_*`

#### B. Integration corpus

使用多文件、小型包结构、真实 Zig 项目片段测试：

- build 成功
- 多规则并发触发
- 排除第三方代码

#### C. Regression corpus

把每次修复的误报/漏报样本沉淀进回归集。

### 13.3 测试原则

- 一条规则至少 3 组正例
- 一条规则至少 3 组反例
- 高置信规则必须有误报防护样本
- 每次 Zig 最新版升级后，优先跑 corpus 回归

---

## 14. CLI / UX 目标

### 14.1 输出层级

首阶段建议支持：

- human-readable CLI
- machine-readable JSON

### 14.2 CLI 信息密度要求

每条诊断至少输出：

- 规则编号
- 严重级别
- 文件:行:列
- 1 行摘要
- 1 段理由
- 1 条建议

### 14.3 退出码策略

建议：

- `0`：无问题或仅 hint
- `1`：存在 warning/error（可配置）
- `2`：build gate 失败 / linter 自身错误

### 14.4 用户配置目标

后续支持：

- 启用/禁用规则
- 调整 severity
- 排除路径
- baseline 文件
- 输出格式

---

## 15. 下一阶段交付物

### 15.1 必做交付物

1. `PLAN.md` 本文档
2. 规则清单草案（含 id、级别、说明、放行条件）
3. AST frontend 内部设计说明
4. corpus 目录规范
5. diagnostics 结构定义文档

### 15.2 建议交付物

1. lint 输出示例
2. suppression 约定草案
3. baseline 机制草案
4. 规则优先级矩阵

---

## 16. 里程碑与验收标准

### Milestone 1：基础设施可用

**完成标准**

- 能对一组 Zig 文件建立 AST
- 能输出稳定 span
- 能注册并运行空规则集
- 能在 build 失败时拒绝进入分析

### Milestone 2：首批规则落地

**完成标准**

- ZAI004、ZAI005、ZAI006、ZAI007 可运行
- 每条规则具备正反例 corpus
- CLI 可输出 rule id / message / span
- 至少有基础 JSON 输出

### Milestone 3：误报治理

**完成标准**

- test/example/generated 识别可用
- suppression 最小功能可用
- 至少 2 条规则具备降级/放行分支
- 回归样本开始积累

### Milestone 4：可在真实项目试用

**完成标准**

- 可在一个中等规模 Zig 项目上稳定运行
- 规则输出可读
- 误报率处于可接受水平
- 对最新版 Zig AST 变动有明确跟进流程

---

## 17. 风险清单

### 17.1 AST 变更风险

由于只追踪最新 Zig，`std.zig.Ast` 结构变化会直接影响本项目。

**应对策略**

- AST 访问集中封装
- 规则层不直接散落底层索引代码
- 每次升级 Zig 时优先修 frontend，不逐条修规则

### 17.2 误报风险

AI-specific 规则天然带启发式。

**应对策略**

- 高置信规则先保守
- 默认规则集控制范围
- 提供 suppression 与 baseline

### 17.3 能力边界风险

AST-only 方案不可能拿到完整语义。

**应对策略**

- 规则设计时明确“基于语法和局部上下文”
- 不宣称做完整 semantic linter
- 对需要语义支持的规则明确标注 future work

### 17.4 项目边界漂移风险

容易从“AI-specific linter”漂成“普通 Zig style checker”。

**应对策略**

- 新规则必须通过第 7 章纳入条件
- 不接受纯审美型规则进入默认集

---

## 18. Future Work（当前阶段不做）

以下内容保留为未来扩展方向：

- 更强的全程序引用分析
- 更强的 `anytype` 实例化统计
- 跨文件 API 暴露/调用关系分析
- JSON/SARIF 完整集成
- 更强的修复建议系统
- 与 build graph 更深入联动

---

## 19. 下一步执行建议

按实际执行顺序，建议立即推进：

1. 固定“只支持最新版 Zig”的项目政策并写入 README
2. 先完成 AST frontend 与 diagnostics 基础层
3. 首批只实现 4 条 P0 规则：
   - ZAI004
   - ZAI005
   - ZAI006
   - ZAI007
4. 同步建立 corpus 与 regression 目录
5. 在规则稳定前，不扩展到泛化 style 规则

---

## 20. 结论

这个 linter 的下一阶段，不应追求“大而全”，而应追求：

- 最新 Zig 版本上稳定
- AST 层实现简洁
- 规则边界明确
- 高置信命中 AI 高发问题
- 在 build-pass 的前提下抓出真正危险的“假 Zig 代码”

如果以上目标达成，这个项目就会具备清晰辨识度：

**它不是普通 Zig linter，而是专门识别 AI 生成 Zig 失真模式的工程化工具。**
