# Zig 标准库覆盖整理

本文基于本机实际安装的 Zig 源码分析，而不是二手资料。

- Zig 版本：`0.16.0-dev.3121+d34b868bc`
- `zig env` 中的标准库目录：`/home/delta/.local/share/mise/installs/zig/master/lib/std`
- 入口文件：`/home/delta/.local/share/mise/installs/zig/master/lib/std/std.zig`

## 分析方法

我主要交叉看了两类内容：

- `std/std.zig` 暴露了哪些公开入口
- 各个入口模块自己的源码注释、公开子模块和目录结构

这样整理出来的结论更接近“标准库当前实际上覆盖了什么”，也更容易看出模块定位和边界。

## 总体结论

从当前源码看，Zig 标准库覆盖面已经很宽，远不只是“容器 + 文件系统 + 格式化”这几个常见印象。它大致已经覆盖这些层级：

- 基础语言支撑：内存、格式化、元编程、数学、Unicode、随机数、日志、测试
- 常用数据结构：数组表、哈希表、位集、链表、优先队列、treap、多数组布局等
- 系统与运行时：I/O、文件、目录、进程、线程、同步原语、时间、终端、动态库
- OS 接口：`std.posix`、`std.os.*`、目标平台信息、对象格式相关类型
- 网络与协议：HTTP、URI、网络 I/O
- 数据编解码：JSON、ZON、Base64、ASCII、文本编码处理
- 压缩与归档：flate/gzip/zlib、lzma、xz、zstd、tar、zip
- 密码学：哈希、AEAD、MAC、KDF、密码哈希、签名、曲线、TLS 相关组件
- 调试与可执行文件格式：DWARF、ELF、Mach-O、COFF、PDB、栈追踪、源码定位
- 构建与 Zig 自身工具链支撑：`std.Build`、`std.zig`、目标描述、
  Zig 源码解析相关 API

换句话说，当前 Zig 标准库已经同时承担了三类角色：

- 应用开发基础库
- 跨平台系统编程库
- Zig 工具链与包管理自身的公共底座

## 按模块整理覆盖范围

## 总览表

| 类别 | 代表模块 | 主要覆盖能力 | 备注 |
| --- | --- | --- | --- |
| 基础设施 | `std.mem` `std.heap` `std.fmt` `std.math` `std.meta` | 内存模型、分配器、格式化、数学、编译期类型操作 | 属于大量其他模块的基础层 |
| 文本与编码 | `std.unicode` `std.ascii` `std.base64` `std.Uri` | UTF-8、ASCII、Base64、URI 解析与处理 | CLI、网络、工具链都会依赖 |
| 容器与集合 | `ArrayList` `HashMap` `ArrayHashMap` `BitSet` `Deque` `PriorityQueue` `Treap` | 常用容器、集合、优先队列、多数组布局 | 不只给原语，也给实用容器 |
| I/O 与运行时 | `std.Io` `std.process` `std.Thread` `std.time` | 文件、目录、网络、进程、线程、同步、终端、睡眠 | `std.Io` 是新一代统一抽象核心 |
| 文件系统 | `std.Io.Dir` `std.Io.File` `std.fs` | 路径、目录、文件、权限、时间戳、内存映射 | `std.fs` 旧入口正逐步迁移 |
| 操作系统接口 | `std.posix` `std.os.*` `std.Target` | POSIX、平台专有 API、目标平台与 ABI 描述 | 偏底层，服务系统编程和交叉编译 |
| 网络与协议 | `std.Io.net` `std.http` `std.Uri` | 网络 I/O、HTTP 客户端/服务端、URI | 当前源码主线明显覆盖 HTTP/1.x |
| 数据格式 | `std.json` `std.zon` | JSON、ZON 的解析与序列化 | 同时支持动态值和静态类型映射 |
| 压缩算法 | `std.compress` | flate、gzip、zlib、lzma、lzma2、xz、zstd | 覆盖主流压缩格式族 |
| 归档格式 | `std.tar` `std.zip` | tar、zip、zip64、解压路径处理 | `tar` 明确只覆盖核心子集 |
| 密码学 | `std.crypto` | 哈希、AEAD、MAC、KDF、密码哈希、签名、曲线、KEM、TLS | 覆盖范围很大，接近独立密码库 |
| 调试与对象格式 | `std.debug` `std.dwarf` `std.elf` `std.macho` `std.coff` `std.pdb` `std.wasm` | 调试信息、对象格式、栈追踪、源码定位 | 同时服务运行时和工具链 |
| 构建系统 | `std.Build` | 构建图、步骤、模块、缓存、watch、fuzz | 是 Zig 官方构建系统的重要实现 |
| Zig 工具链 API | `std.zig` | Tokenizer、AST、ZIR、目标推导、编译器相关辅助 | 明确无稳定 API 保证 |

## 代表入口速查表

| 模块 | 源码中能看到的代表入口 | 能力概括 |
| --- | --- | --- |
| `std.mem` | `Allocator` `Alignment` | 内存与切片基础模型 |
| `std.heap` | `ArenaAllocator` `DebugAllocator` `PageAllocator` | 多种分配器与调试分配 |
| `std.fmt` | `Parser` `Options` | 格式化与格式串解析 |
| `std.math` | `sqrt` `pow` `approxEqAbs` | 数值函数与浮点工具 |
| `std.meta` | `stringToEnum` `Child` `Elem` | 编译期类型辅助 |
| `std.Io` | `Dir` `File` `Reader` `Writer` `net` | 统一 I/O 与并发抽象 |
| `std.process` | `Child` `Args` `Environ` | 进程、参数、环境变量 |
| `std.posix` | 常量、结构体、socket/FD 相关类型 | 底层 POSIX API 层 |
| `std.http` | `Client` `Server` `HeadParser` | HTTP 客户端、服务端、协议解析 |
| `std.json` | `Scanner` `Value` `parseFromSlice` `Stringify` | JSON 扫描、解析、序列化 |
| `std.zon` | `parse` `stringify` `Serializer` | ZON 解析与输出 |
| `std.compress` | `flate` `lzma` `xz` `zstd` | 压缩格式实现 |
| `std.tar` | `Writer` `ExtractOptions` | tar 读写与提取核心能力 |
| `std.zip` | `EndRecord` `Decompress` | zip 结构解析与解压 |
| `std.crypto` | `aead` `hash` `sign` `pwhash` `tls` | 现代密码学与 TLS 组件 |
| `std.debug` | `Dwarf` `ElfFile` `MachOFile` `Coverage` | 调试信息与栈追踪 |
| `std.Build` | `Step` `Module` `Cache` `Watch` | 构建系统实现 |
| `std.zig` | `Tokenizer` `Ast` `Zir` `ErrorBundle` | Zig 编译器相关 API |

## 1. 基础设施与通用能力

### `std.mem`

`mem.zig` 是非常核心的一层，不只是“切片操作”。源码里可以直接看到：

- `Allocator` 抽象
- `Alignment` 对齐模型
- 分配器校验包装 `ValidationAllocator`
- 大量围绕字节、切片、对齐、序列、复制、比较的基础能力

这说明 `std.mem` 本质上是 Zig 运行时风格 API 的基础层之一。

### `std.heap`

`heap.zig` 暴露了多种分配器和页大小相关能力，包括：

- `ArenaAllocator`
- `FixedBufferAllocator`
- `PageAllocator`
- `SmpAllocator`
- `DebugAllocator`
- `MemoryPool`
- `c_allocator`

这部分覆盖的是“内存分配策略”和“调试/页级管理”，不是单一 allocator。

### `std.fmt`

`fmt.zig` 顶部就写明是 “String formatting and parsing”。源码可见它不仅有格式化输出，还包括：

- 占位符解析器 `Parser`
- 数字格式模式
- 浮点格式化支持
- 宽度、精度、对齐、填充等控制

所以它覆盖的是一整套格式化语义，而不是简单的 `print`。

### `std.math`

`math.zig` 中除了常数外，还有：

- 浮点表示与边界值工具
- 近似比较 `approxEqAbs`、`approxEqRel`
- `sqrt`、`pow`、`ldexp`、`frexp`、`modf` 等数学函数
- `nan`、`inf`、符号与分类判断

属于完整的数值基础库。

### `std.meta`

`meta.zig` 是 Zig 反射/元编程辅助层，源码中能直接看到：

- `stringToEnum`
- `alignment`
- `Child`、`Elem`
- `sentinel`、`Sentinel`
- 容器布局信息

这部分主要服务于泛型编程和编译期类型操作。

### 其他通用模块

从 `std.zig` 和目录结构还能看到这些通用能力：

- `std.ascii`
- `std.unicode`
- `std.base64`
- `std.log`
- `std.Random`
- `std.sort`
- `std.simd`
- `std.atomic`
- `std.debug`
- `std.testing`

其中：

- `unicode.zig` 明确覆盖 UTF-8 编码、解码、校验、计数等
- `base64.zig` 明确实现 RFC 4648 的标准/URL-safe 编解码
- `testing.zig` 提供测试分配器、断言、错误断言、测试 I/O 等测试基建

## 2. 数据结构与集合

`std/std.zig` 直接暴露了很多现成容器和集合类型：

- `ArrayList`
- `HashMap` / `AutoHashMap` / `StringHashMap`
- `ArrayHashMap` / `StringArrayHashMap`
- `StaticStringMap`
- `BitSet` 相关
- `Deque`
- `PriorityQueue`
- `PriorityDequeue`
- `SinglyLinkedList`
- `DoublyLinkedList`
- `Treap`
- `MultiArrayList`

这说明 Zig 标准库并不是只给最低层原语，也提供了相当实用的容器层。

特别是 `MultiArrayList` 这种偏数据布局优化的结构，也说明标准库覆盖到了偏系统性能导向的使用场景。

## 3. I/O、文件系统、进程、并发

### `std.Io`

`Io.zig` 的开头注释非常关键，源码明确写了它要抽象这些内容：

- 文件系统
- 网络
- 进程
- 时间与睡眠
- 随机数
- async / await / concurrent / cancel
- 并发队列
- wait groups 和 select
- mutex/futex/event/condition
- 内存映射文件

也就是说，当前的 `std.Io` 并不是“读写流”那么简单，而是在朝一个跨平台 I/O 与并发统一抽象层发展。

从目录 `std/Io/` 也能看到：

- `Dir.zig`
- `File.zig`
- `Reader.zig`
- `Writer.zig`
- `Terminal.zig`
- `net.zig`
- `RwLock.zig`
- `Semaphore.zig`
- `Threaded.zig`
- `Uring.zig`
- `Kqueue.zig`
- `Dispatch.zig`

这说明它已经把不同平台的事件模型也纳入抽象范围。

### `std.fs`

`fs.zig` 现在很薄，源码里不少内容都标记成 deprecated，并指向 `std.Io.Dir`。这说明：

- 文件系统能力没有消失
- 只是标准库正在把旧的 `fs` 入口逐步迁移到新的 `Io` 抽象下

所以今天看 Zig 标准库文件系统能力，重点应该放在
`std.Io.Dir` / `std.Io.File`，而不是旧 `std.fs` 表层。

### `std.process`

`process.zig` 覆盖内容包括：

- 子进程 `Child`
- 参数 `Args`
- 环境变量 `Environ`
- 当前路径、可执行文件路径
- 用户信息查询
- 进程初始化 `Init`

它是高于 `posix` 的进程层封装。

### `std.Thread`

`std.zig` 直接暴露 `Thread`，再结合 `Io`/`testing`/`crypto` 里对线程和并发的使用，可以判断标准库已经覆盖：

- 线程创建与管理
- 同步原语
- 线程相关错误模型

并发不是外挂能力，而是标准库的主线能力之一。

## 4. 操作系统接口与平台抽象

### `std.posix`

`posix.zig` 开头注释写得很清楚：

- 它比 OS 专有 API 更跨平台
- 但又比 `std.Io`、`std.process` 更底层、更不便携

源码里还能看到它暴露了大量 POSIX 常量、结构体、socket 相关类型、文件描述符相关类型、权限与信号等内容。

所以 `std.posix` 的定位很明确：

- 给系统编程使用
- 但不承担“最高层可移植 API”角色

### `std.os`

`std/os/` 目录下有：

- `linux.zig`
- `windows.zig`
- `wasi.zig`
- `uefi.zig`
- `plan9.zig`
- `emscripten.zig`

这说明 Zig 标准库对平台专有接口也有直接建模。

### `std.Target`

`Target.zig` 顶部写的是“执行代码的机器的全部细节”。它覆盖：

- CPU
- OS
- ABI
- 对象文件格式
- 动态链接器
- 版本范围

而且源码里能看到大量 OS tag，包括 Linux、BSD、Darwin、
Windows、WASI、Emscripten、GPU/图形相关 target 等。

这部分是 Zig 交叉编译能力和工具链推导的重要基础。

## 5. 网络与协议

### `std.http`

`http.zig` 直接暴露：

- `Client`
- `Server`
- `HeadParser`
- `ChunkParser`
- `HeaderIterator`

并且源码里明确列出：

- HTTP 方法枚举
- 状态码枚举
- 当前版本主要是 `HTTP/1.0` 和 `HTTP/1.1`

所以标准库已经覆盖 HTTP 客户端/服务端和协议解析，不只是 socket。

### 网络 I/O

`std.Io` 中明确包含 networking，且 `std/Io/net.zig` 独立存在。因此网络能力主要放在：

- `std.Io.net`
- `std.http`
- `std.Uri`

这是一套从底层连接到上层协议都覆盖到的结构。

## 6. 数据格式、文本与序列化

### `std.json`

`json.zig` 顶部注释写明它实现 RFC 8259，并且源码直接包含：

- 低层 `Scanner` / `Token`
- `Reader`
- 动态 `Value`
- 高层 `parseFromSlice`
- `stringify`

所以它同时覆盖：

- 词法扫描
- 动态 JSON 值模型
- 静态类型反序列化
- 序列化输出

### `std.zon`

`zon.zig` 说明它支持 ZON 的解析和字符串化。源码里明确写到：

- ZON 是 Zig Object Notation
- 语法基本是 Zig 语法的子集
- 支持布尔、数字、字符、枚举、`null`、字符串、多行字符串
- 支持匿名 struct 和 tuple

这意味着 Zig 标准库不仅支持通用 JSON，也支持 Zig 自己生态里的配置/对象表示格式。

### 其他文本与编码

还包括：

- `std.base64`
- `std.ascii`
- `std.unicode`
- `std.Uri`

其中 `unicode.zig` 覆盖 UTF-8 基础处理，这对 CLI、编译器、工具链都很重要。

## 7. 压缩与归档

### `std.compress`

`compress.zig` 明确暴露：

- `flate`，注释里特别说明 gzip 和 zlib 在这里
- `lzma`
- `lzma2`
- `xz`
- `zstd`

这说明标准库已经覆盖主流压缩算法族，不只是 deflate。

### `std.tar`

`tar.zig` 的源码注释很有价值，它明确说：

- 支持 tar 基础格式和 GNU / POSIX pax 扩展中的一部分
- 但“不是 comprehensive tar parser”
- 重点只覆盖 Zig 包管理需要的文件、目录、符号链接和部分属性

所以这部分能力是“可用且带明确边界”的，不应理解成完整通用 tar 工具箱。

### `std.zip`

`zip.zig` 直接实现 ZIP 文件结构，包括：

- 本地文件头
- 中央目录
- ZIP64 结构
- `store` 和 `deflate` 解压路径

这说明标准库也覆盖常见归档格式读取/处理。

## 8. 密码学与 TLS

### `std.crypto`

这是当前 Zig 标准库覆盖面非常大的一个部分。`crypto.zig` 源码直接分出这些大类：

- `aead`
- `auth`
- `core`
- `dh`
- `kem`
- `ecc`
- `hash`
- `kdf`
- `onetimeauth`
- `pwhash`
- `sign`
- `stream`

从具体算法上看，源码目录和入口里直接能看到：

- AES、AES-GCM、AES-GCM-SIV、AES-SIV、AES-OCB、AES-CCM
- ChaCha20 / XChaCha20 / Poly1305
- Blake2、Blake3、SHA-1、SHA-2、SHA-3、MD5
- HMAC、SipHash、CMAC、CBC-MAC
- X25519、Ed25519、P256、P384、Secp256k1、Ristretto255
- Argon2、bcrypt、scrypt、PBKDF2、HKDF
- ML-KEM、ML-DSA 等后量子相关实现
- `tls.zig` 和 `crypto/tls/` 目录

这说明 Zig 标准库并没有把密码学完全留给第三方库，而是内置了相当完整的一套现代密码学组件。

## 9. 调试信息、对象格式与可执行文件相关能力

### 对象格式与调试信息

`std.zig` 入口直接暴露这些模块：

- `coff`
- `elf`
- `macho`
- `wasm`
- `dwarf`
- `pdb`
- `debug`

其中 `debug.zig` 源码里明确可见：

- `Dwarf`
- `Pdb`
- `ElfFile`
- `MachOFile`
- `Info`
- `Coverage`
- 栈展开、源码位置解析、自身调试信息读取

这说明标准库不只是“能打印 panic”，而是覆盖到：

- 调试信息读取
- 地址到源码位置映射
- 平台相关栈追踪
- 覆盖率支持

### 动态库与版本语义

另外还包括：

- `dynamic_library.zig`
- `SemanticVersion.zig`

属于工具链和系统库交互时经常会用到的基础能力。

## 10. 构建系统与 Zig 自身工具链 API

### `std.Build`

`Build.zig` 不是一个小工具模块，而是一整套构建图与步骤系统。源码中能直接看到：

- `Cache`
- `Step`
- `Module`
- `Watch`
- `Fuzz`
- `WebServer`
- 目标、缓存、依赖、安装目录、系统库选项、跨平台运行器支持

也就是说，Zig 标准库里包含了 Zig 官方构建系统本身的大量实现。

### `std.zig`

`zig.zig` 源码开头直接说明：这里放的是 Zig 编译器分发包中一部分
“以源码形式分发”的内容，而且“没有 API 稳定性保证”。

这个命名空间当前覆盖了：

- `Tokenizer`
- `Ast`
- `AstGen`
- `Zir`
- `Zoir`
- `ZonGen`
- `ErrorBundle`
- `BuiltinFn`
- `LibCInstallation`
- `WindowsSdk`
- `target`
- `llvm`
- C translation 辅助

所以它本质上是“Zig 编译器和工具链内部能力的一部分对外暴露”，而不是普通意义上的稳定应用库。

## 11. 当前源码里能看出的边界

看源码时也能明显看到一些边界，不适合把它说成“什么都全了”：

- `std.fs` 旧入口正在淡出，能力集中到 `std.Io`
- `std.tar` 明确不是完整 tar 解析器，只覆盖包管理需要的核心子集
- `std.zig` 明确没有 API 稳定性保证
- `std.http` 当前入口里明确是 HTTP/1.0 和 HTTP/1.1，不代表已经把所有现代 HTTP 层能力都做满
- 一些平台能力会根据目标平台、是否链接 libc、后端能力而变化

所以更准确的说法是：

- 标准库覆盖面很广
- 很多模块已经能直接用于生产级系统编程
- 但其中一部分模块仍处在演进中，尤其是新 `Io` 抽象和偏工具链内部的部分

## 12. 一句话总结

如果按当前 `0.16.0-dev` 这份源码来概括，Zig 标准库已经覆盖了：

- 通用基础库
- 容器与内存管理
- 跨平台系统 I/O 与进程/线程能力
- POSIX 与平台专有接口
- 网络与 HTTP
- JSON/ZON 等数据格式
- 压缩、归档
- 现代密码学
- 调试信息与对象文件格式
- Zig 构建系统与编译器相关工具链 API

它现在更像是一套“系统编程 + 工具链 + 应用基础设施”的综合标准库，而不是只提供几个基础容器的轻量标准库。
