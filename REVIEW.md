# Review: 标准库覆盖情况

## Scope

- 依据：`docs/zig-std-quick-reference.md`
- Zig 版本基线：`0.16.0-dev.3121+d34b868bc`
- 审查范围：仅审库包，不审可执行程序入口
- 审查目标：找出项目内已经被 Zig 标准库直接覆盖，或高度重叠的函数、方法、实现与抽象层

## Method

- 先按库包扫描公共 API 和核心实现
- 再与本机 `std` 源码交叉核对实际入口，而不是按印象判断
- 只把“标准库已经有同类能力”记为问题；如果项目是在 `std` 之上做工程化封装，则单独说明边界，不强行算重复实现

## Findings

### High

#### 1. `zest/src/status.zig` 基本完整重写了 `std.http.Status`

- 结论：这是当前最明确、最完整的一处重复实现。
- 项目位置：`zest/src/status.zig:3-174`
- 对应标准库：`std.http.Status`，见 `std/http.zig:93-257`
- 证据：
  - 项目里自定义了完整 HTTP 状态码枚举、状态文本和状态分类：`code()`、`text()`、`isInformational()`、`isSuccess()`、`isRedirection()`、`isClientError()`、`isServerError()`、`isError()`。
  - 标准库已经提供同类能力：`std.http.Status`、`phrase()`、`class()`。
  - `zest` 最终仍要把自定义状态转回标准库状态再响应：`zest/src/server.zig:141-146`。
- 风险评估：
  - 维护两份状态码表，后续标准库新增或修正状态时容易漂移。
  - API 使用方需要在 `zest.Status` 和 `std.http.Status` 之间来回转换。
  - 这类协议枚举本身没有明显产品差异，重复维护收益很低。
- 建议动作：
  - 优先评估直接以 `std.http.Status` 作为对外状态类型。
  - 若必须保留兼容层，也应收敛成薄别名/适配层，而不是继续自维护完整表。

#### 2. `zjwt` 的 base64url 编解码已被 `std.base64` 直接覆盖

- 结论：`zjwt` 在手工实现 JWT 所需的 base64url 变体，但标准库已提供等价入口。
- 项目位置：`zjwt/src/token.zig:56-105`
- 对应标准库：`std.base64.url_safe`、`std.base64.url_safe_no_pad`，见 `std/base64.zig:62-80`
- 证据：
  - `base64UrlEncode()` 先用 `std.base64.standard.Encoder` 编码，再手工把 `+` 改成 `-`、`/` 改成 `_`，最后去掉 `=` padding。
  - `base64UrlDecode()` 则反向补 `=`、再把 `-`/`_` 改回标准 Base64 字母表后解码。
  - 标准库已经直接暴露 RFC 4648 section 5 的 URL-safe codec，而且还区分了带 padding 与无 padding 两套接口。
  - 这两个 helper 还被公开导出：`zjwt/src/root.zig:9-10`。
- 风险评估：
  - 手工转换路径更容易引入边界 bug。
  - 对外暴露重复 API，会放大后续迁移成本。
  - 标准库后续若优化 codec 行为或错误模型，项目无法自然受益。
- 建议动作：
  - 优先评估改为直接建立在 `std.base64.url_safe_no_pad` 上。
  - 如果保留 helper，建议只保留 JWT 语义包装，不再保留字符替换和 padding 逻辑本体。

### Medium

#### 3. `zcli` / `ztui` 的终端颜色能力与 `std.Io.Terminal` 明显重叠

- 结论：颜色枚举、ANSI 转义、TTY 模式探测里，项目已经和标准库进入明显重叠区。
- 项目位置：
  - `zcli/src/color.zig:3-39`
  - `ztui/src/style.zig:1-27`
  - `ztui/src/terminal.zig:21-34`
- 对应标准库：`std.Io.Terminal.Color`、`std.Io.Terminal.Mode.detect()`、`std.Io.Terminal.setColor()`，见 `std/Io/Terminal.zig:15-140`
- 证据：
  - `zcli` 自己维护 `Style -> ANSI prefix` 映射，并只用 `NO_COLOR` 决定是否着色。
  - `ztui` 自己维护整套 ANSI 样式字符串。
  - 标准库已经提供跨平台终端颜色、模式探测和 Windows/ANSI 兼容处理。
  - `std.Io.Terminal.Mode.detect()` 还处理了 `NO_COLOR`、`CLICOLOR_FORCE`、TTY 检测和 Windows 控制台差异，这部分比项目实现更完整。
- 风险评估：
  - 当前实现偏 ANSI/类 Unix 假设，跨平台语义与标准库可能逐渐分叉。
  - 环境变量与终端能力探测逻辑若持续自维护，会和 `std` 的行为模型产生不一致。
  - 终端颜色本身不是这几个库的核心业务能力，重复维护性价比偏低。
- 建议动作：
  - 颜色设置和模式探测优先考虑收敛到 `std.Io.Terminal`。
  - 项目可保留自身的“语义样式”层，例如 `title`/`heading`/`accent`，但底层颜色落点不必重复实现。
  - `ztui/src/terminal.zig` 里的清屏、备用屏、光标控制属于更高层终端行为，当前不能简单算被 `std` 完全替代；这部分可保留观察。

#### 4. `zlog/src/level.zig` 与 `std.log.Level` 高度重叠

- 结论：日志级别类型本身没有明显新增能力，更多是在重复包装标准库现成模型。
- 项目位置：`zlog/src/level.zig:3-27`
- 对应标准库：`std.log.Level`，见 `std/log.zig:30-50`
- 证据：
  - 项目里定义了 `trace/debug/info/warn/err`，并提供 `asString()`、`fromString()`。
  - 标准库已经提供 `std.log.Level` 和 `asText()`。
  - `zlog` 真正有差异化的是 `Record`、`Field`、`Sink`、环境配置等，不是 level 枚举本身。
- 风险评估：
  - 与 `std.log` 的等级语义若发生细微偏移，会影响对接和适配。
  - 日志级别在生态里本来就是共享概念，重复定义会增加边界转换。
- 建议动作：
  - 优先评估是否直接复用 `std.log.Level`。
  - 若保留自定义 level，建议明确说明它相对 `std.log.Level` 的额外价值，否则会显得重复层过厚。

#### 5. `zest` 的 HTTP 传输层大部分是对 `std.http.Server` / `std.Io.net` 的再包装

- 结论：`zest` 的增量价值主要在路由、中间件和上下文；HTTP server 传输层本身并不构成明显独立能力。
- 项目位置：`zest/src/server.zig:45-147`
- 对应标准库：`std.http.Server`、`std.http.Method`、`std.http.Status`、`std.Io.net`
- 证据：
  - `listen()` 直接建立在 `net.IpAddress.listen()` 和 `accept()` 上。
  - `handleConnection()` 直接构造 `http.Server.init(...)` 并调用 `receiveHead()`。
  - `sendResponse()` 最终通过 `request.respond(...)` 回写响应。
  - `App` 层 `get/post/put/delete/...` 也是围绕 `Server` 做更高层 API 封装：`zest/src/app.zig:35-69`。
- 风险评估：
  - 如果外部认知把 `zest` 视为“自有 HTTP server 实现”，会模糊与 `std.http` 的边界。
  - 后续标准库 HTTP API 演进时，包装层可能需要同步调整。
- 建议动作：
  - 文档上应更明确地把 `zest` 定位成 `std.http` 之上的 web 框架层，而不是底层 HTTP 实现。
  - 优先把独特价值集中在 routing/context/middleware，而不是复制协议层概念。

### Low

#### 6. 一些 JSON helper 只是对 `std.json` 的薄包装

- 结论：这类 API 可以存在，但严格说不构成新的基础能力。
- 项目位置：
  - `zcli/src/format.zig:9-26`
  - `zest/src/context.zig:98-107`
  - `zest/src/context.zig:140-142`
  - `zjwt/src/token.zig:10-23`
- 对应标准库：`std.json.stringify()`、`std.json.parseFromSlice()`、`std.json.fmt(...)`，见 `std/json.zig:10,96-119`
- 证据：
  - `zcli.writeJson()` 主要是给 `std.json.stringify()` 外包一层参数和颜色输出。
  - `Context.json()` / `Context.jsonStatus()` 本质上也是设置 header 后调用 `std.json.stringify()`。
  - `Context.bodyJson()` 直接调用 `std.json.parseFromSlice()`。
  - `Header.toJson()` 也是构造 map 后调用 `std.json.stringify()`。
- 风险评估：
  - 风险不高，因为这些 helper 更偏 convenience API。
  - 但如果作为独立模块价值宣传，会显得与 `std.json` 边界不清。
- 建议动作：
  - 保留这类 API 没问题，但建议在文档中明确其定位是“场景化辅助函数”，不是 JSON 基础设施替代品。

## Non-findings

### `ztoml`

- 当前不算标准库覆盖问题。
- 原因：本机 Zig `std` 没有 TOML 解析/序列化模块，`ztoml` 仍然提供标准库没有的格式能力。

### `ztmpfile`

- 当前不算“已被 `std` 直接覆盖”。
- 原因：虽然它建立在 `std.Io.Dir`、`std.Io.File`、随机数和文件系统原语之上，但标准库没有同等级的 temp file/temp dir 生命周期库。
- 边界说明：`std.testing.tmpDir()` 只覆盖测试场景临时目录，不等价于通用库抽象，见 `std/testing.zig:634-655`。

## Open Questions

1. `zest.Status` 是否有任何必须区别于 `std.http.Status` 的对外兼容要求？如果没有，这一层最值得优先收敛。
2. `zjwt` 暴露自定义 base64url helper，是否是为了稳定外部 API，还是仅仅因为实现时未直接采用 `std.base64.url_safe_no_pad`？
3. `zcli` / `ztui` 是否明确要求覆盖 `std.Io.Terminal` 尚未涵盖的终端行为？如果只是颜色输出，当前抽象层偏厚。
4. `zlog` 是否计划与 `std.log` 深度集成？如果是，自定义 `Level` 会成为多余边界。

## Summary

- 最明确的重复实现有两处：`zest.Status` 与 `zjwt` 的 base64url。
- 中等程度重叠集中在终端颜色层、日志级别层，以及 `zest` 对 `std.http` 的包装边界。
- `ztoml`、`ztmpfile` 当前不应被误判为“已被标准库覆盖”。
- 如果后续要做收敛，建议优先顺序是：
  1. `zest.Status`
  2. `zjwt` base64url helper
  3. `zcli` / `ztui` 颜色与终端模式层
  4. `zlog.Level`
