const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");
const rule_ids = @import("../rule_ids.zig");

const targeted_builtin_tags = [_]std.zig.Ast.Node.Tag{
    .builtin_call_two,
    .builtin_call_two_comma,
    .builtin_call,
    .builtin_call_comma,
};

const CastKind = enum {
    ptrCast,
    alignCast,
    constCast,
    bitCast,

    fn label(self: CastKind) []const u8 {
        return switch (self) {
            .ptrCast => "@ptrCast",
            .alignCast => "@alignCast",
            .constCast => "@constCast",
            .bitCast => "@bitCast",
        };
    }
};

const ChainInfo = struct {
    kinds: [8]CastKind = undefined,
    len: usize = 0,

    fn allConstCast(self: ChainInfo) bool {
        if (self.len == 0) return false;
        for (self.kinds[0..self.len]) |kind| {
            if (kind != .constCast) return false;
        }
        return true;
    }
};

pub fn run(ctx: *RuleContext) !void {
    if (ctx.shouldSkipFile()) return;

    var severity = Severity.warning;
    if (ctx.config.rules.suspicious_cast_chain) |cfg| {
        severity = Severity.fromString(cfg.base.severity) orelse Severity.warning;
    }

    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        if (!isBuiltinCallTag(tag)) continue;

        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (ctx.shouldSkipNode(node)) continue;
        ctx.traceNodeBestEffort(2, node, "inspect");

        if (hasTargetedParent(ast, tags, node)) continue;

        const info = buildChain(ast, node) orelse continue;
        if (info.len < 2 or info.allConstCast()) continue;

        const loc = locations.getNodeLocation(ast, node, ctx.file.content);
        const message = try formatMessage(ctx.allocator, info);
        const classified = classifySeverity(severity, ast, node, info);
        ctx.traceNodeBestEffort(2, node, "match");
        try ctx.addDiagnostic(rule_ids.suspicious_cast_chain, classified, loc.line, loc.column, message);
    }
}

fn isBuiltinCallTag(tag: std.zig.Ast.Node.Tag) bool {
    inline for (targeted_builtin_tags) |candidate| {
        if (tag == candidate) return true;
    }
    return false;
}

fn buildChain(ast: std.zig.Ast, start: std.zig.Ast.Node.Index) ?ChainInfo {
    var info = ChainInfo{};
    var current = start;

    while (true) {
        const kind = castKind(ast, current) orelse break;
        if (info.len >= info.kinds.len) break;
        info.kinds[info.len] = kind;
        info.len += 1;

        current = firstArg(ast, current) orelse break;
    }

    return if (info.len > 0) info else null;
}

fn castKind(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) ?CastKind {
    if (!isBuiltinCallTag(ast.nodeTag(node))) return null;
    const token = ast.nodes.items(.main_token)[@intFromEnum(node)];
    const name = ast.tokenSlice(token);
    if (std.mem.eql(u8, name, "@ptrCast")) return .ptrCast;
    if (std.mem.eql(u8, name, "@alignCast")) return .alignCast;
    if (std.mem.eql(u8, name, "@constCast")) return .constCast;
    if (std.mem.eql(u8, name, "@bitCast")) return .bitCast;
    return null;
}

fn firstArg(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) ?std.zig.Ast.Node.Index {
    var buffer: [2]std.zig.Ast.Node.Index = undefined;
    const params = ast.builtinCallParams(&buffer, node) orelse return null;
    if (params.len == 0) return null;
    return params[0];
}

fn hasTargetedParent(
    ast: std.zig.Ast,
    tags: []const std.zig.Ast.Node.Tag,
    child: std.zig.Ast.Node.Index,
) bool {
    for (tags, 0..) |tag, i| {
        if (!isBuiltinCallTag(tag)) continue;

        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (node == child) continue;
        if (castKind(ast, node) == null) continue;

        const arg = firstArg(ast, node) orelse continue;
        if (arg == child) return true;
    }
    return false;
}

fn classifySeverity(default_severity: Severity, ast: std.zig.Ast, node: std.zig.Ast.Node.Index, info: ChainInfo) Severity {
    if (default_severity == .help) return .help;
    if (isLowRiskOpaqueContextBridge(ast, node, info)) return .help;
    return default_severity;
}

fn isLowRiskOpaqueContextBridge(ast: std.zig.Ast, node: std.zig.Ast.Node.Index, info: ChainInfo) bool {
    if (info.len != 2) return false;

    const outer = info.kinds[0];
    const inner = info.kinds[1];

    if (outer == .ptrCast and inner == .alignCast) {
        const inner_node = firstArg(ast, node) orelse return false;
        const source = firstArg(ast, inner_node) orelse return false;
        return switch (ast.nodeTag(source)) {
            .identifier, .field_access => true,
            else => false,
        };
    }

    if (outer == .ptrCast and inner == .constCast) {
        const inner_node = firstArg(ast, node) orelse return false;
        const source = firstArg(ast, inner_node) orelse return false;
        return ast.nodeTag(source) == .address_of;
    }

    return false;
}

fn formatMessage(allocator: std.mem.Allocator, info: ChainInfo) ![]const u8 {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "suspicious cast chain: ");
    for (info.kinds[0..info.len], 0..) |kind, i| {
        if (i != 0) try buf.appendSlice(allocator, " -> ");
        try buf.appendSlice(allocator, kind.label());
    }

    return buf.toOwnedSlice(allocator);
}

fn expectRuleHitsWithAllocator(
    allocator: std.mem.Allocator,
    source: []const u8,
    path: []const u8,
    expected_warning: usize,
    expected_help: usize,
) !void {
    const content = try allocator.dupeZ(u8, source);
    defer allocator.free(content);

    var ast = try std.zig.Ast.parse(allocator, content, .zig);
    defer ast.deinit(allocator);

    const SourceFile = @import("../source_file.zig").SourceFile;
    const IgnoreDirectives = @import("../ignore_directives.zig").IgnoreDirectives;
    const DiagnosticCollection = @import("../diagnostic.zig").DiagnosticCollection;
    const Config = @import("../config.zig").Config;

    var file = SourceFile{
        .allocator = allocator,
        .path = path,
        .content = content,
        .ast = ast,
    };

    var ignores = try IgnoreDirectives.parse(allocator, source);
    defer ignores.deinit();

    var diagnostics = DiagnosticCollection.init(allocator);
    defer diagnostics.deinit();

    const cfg = Config{
        .rules = .{
            .suspicious_cast_chain = .{},
        },
    };

    var ctx = RuleContext{
        .allocator = allocator,
        .file = &file,
        .config = cfg,
        .ignores = &ignores,
        .diagnostics = &diagnostics,
    };

    try run(&ctx);

    var warnings: usize = 0;
    var helps: usize = 0;
    for (diagnostics.items.items) |d| {
        try std.testing.expectEqualStrings(rule_ids.suspicious_cast_chain, d.rule_id);
        switch (d.severity) {
            .warning => warnings += 1,
            .help => helps += 1,
            else => return error.UnexpectedSeverity,
        }
    }

    try std.testing.expectEqual(expected_warning, warnings);
    try std.testing.expectEqual(expected_help, helps);
}

test "detects mixed cast chain with bitCast" {
    const source =
        \\fn demo(ptr: *anyopaque) void {
        \\    const raw: usize = @bitCast(@ptrCast(ptr));
        \\    _ = raw;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, "src/sample.zig", 1, 0);
}

test "detects three-step cast chain" {
    const source =
        \\fn demo(ptr: *anyopaque) void {
        \\    const out: usize = @bitCast(@ptrCast(@alignCast(ptr)));
        \\    _ = out;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, "src/sample.zig", 1, 0);
}

test "downgrades common ptrCast alignCast opaque restore to help" {
    const source =
        \\fn demo(ctx: *anyopaque) void {
        \\    const self: *const u8 = @ptrCast(@alignCast(ctx));
        \\    _ = self;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, "src/sample.zig", 0, 1);
}

test "downgrades common ptrCast constCast address bridge to help" {
    const source =
        \\fn demo(value: *const u8) void {
        \\    const ctx: *anyopaque = @ptrCast(@constCast(value));
        \\    _ = ctx;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, "src/sample.zig", 0, 1);
}

test "ignores standalone constCast" {
    const source =
        \\fn demo(value: *const u8) void {
        \\    const ctx = @constCast(value);
        \\    _ = ctx;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, "src/sample.zig", 0, 0);
}

test "ignores skipped test path" {
    const source =
        \\fn demo(ptr: *anyopaque) void {
        \\    const raw: usize = @bitCast(@ptrCast(ptr));
        \\    _ = raw;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, "src/sample_test.zig", 0, 0);
}
