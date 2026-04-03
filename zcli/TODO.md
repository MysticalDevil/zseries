# zcli 待完善能力

## P0 - 核心能力

### 参数解析

- [x] 位置参数解析 (`args.positionalArg`)
- [x] 短选项 (`-f`) / 长选项 (`--flag`) (`args.hasFlag`, `args.flagValue`)
- [x] 子命令路由 (`args.Subcommand`, `args.routeSubcommand`)
- [x] 参数验证与类型转换 (`args.flagValueInt`)
- [ ] 自动生成 `--help`

### 输入/输出

- [ ] 表格输出 (table)
- [ ] JSON/YAML 格式化输出
- [ ] 分页显示 (pager)
- [x] 进度条 (progress bar) - 已在 ztui/widgets.zig 实现

### 交互提示

- [ ] 多选菜单 (select)
- [x] 密码输入 (隐藏回显)
- [x] 确认对话框 (y/n)
- [x] 默认值支持 (confirm)

### 错误处理

- [ ] 统一错误类型定义
- [ ] 错误消息格式化
- [ ] 退出码管理

## P1 - 扩展能力

- [ ] 分级日志 (debug/info/warn/error)
- [ ] 配置文件读取 (JSON/YAML/TOML)
- [ ] 环境变量支持
- [ ] Shell 补全生成 (bash/zsh/fish)

## P2 - 辅助能力

- [ ] 版本信息输出 (`--version`)
- [ ] CLI 测试辅助工具
- [ ] 自动文档生成
- [ ] 管道/流处理支持

## 已完成

- [x] ANSI 颜色样式 (`src/color.zig`)
- [x] 帮助文本渲染 (`src/helpfmt.zig`)