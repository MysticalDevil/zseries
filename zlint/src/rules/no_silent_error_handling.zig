const std = @import("std");
const RuleContext = root.RuleContext;
const Severity = diagnostic.Severity;
const locations = @import("../ast/locations.zig");
const rule_ids = @import("../rule_ids.zig");
const root = @import("root.zig");
const diagnostic = @import("../diagnostic.zig");
const source_file = @import("../source_file.zig");
const ignore_directives = @import("../ignore_directives.zig");
const config_zig = @import("../config.zig");

pub fn run(ctx: *RuleContext) !void {
    if (ctx.shouldSkipFile()) return;

    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    var severity = Severity.warning;
    if (ctx.config.rules.no_silent_error_handling) |cfg| {
        severity = Severity.fromString(cfg.base.severity) orelse Severity.warning;
    }

    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (ctx.shouldSkipNode(node)) continue;
        if (tag == .@"catch") {
            try checkFallbackBranch(ctx, node, severity, .err_union);
        }
    }

    try checkEmptySwitchElseByAst(ctx, severity);
}

const FallbackKind = enum {
    err_union,
};

fn checkFallbackBranch(ctx: *RuleContext, node: std.zig.Ast.Node.Index, severity: Severity, kind: FallbackKind) !void {
    const ast = ctx.file.ast;
    const rhs = ast.nodeData(node).node_and_node[1];
    const rhs_tag = ast.nodeTag(rhs);

    if (rhs_tag == .unreachable_literal) return;
    if (kind == .err_union and rhs_tag == .identifier) {
        const token = ast.nodes.items(.main_token)[@intFromEnum(rhs)];
        if (std.mem.eql(u8, ast.tokenSlice(token), "null")) return;
    }
    if (isSilentExit(ast, ctx.file.content, rhs, rhs_tag)) {
        const loc = locations.getNodeLocation(ast, node, ctx.file.content);
        try ctx.addDiagnostic(
            rule_ids.no_silent_error_handling,
            severity,
            loc.line,
            loc.column,
            silentExitMessage(kind),
        );
        return;
    }

    if (rhs_tag == .block or rhs_tag == .block_semicolon or rhs_tag == .block_two or rhs_tag == .block_two_semicolon) {
        if (isEmptyBlock(ast, rhs, ctx.file.content)) {
            if (isInsideCatchBlock(ast, node)) return;
            const loc = locations.getNodeLocation(ast, node, ctx.file.content);
            try ctx.addDiagnostic(
                rule_ids.no_silent_error_handling,
                severity,
                loc.line,
                loc.column,
                emptyBlockMessage(kind),
            );
        }
    }
}

fn isSilentExit(ast: std.zig.Ast, source: []const u8, node: std.zig.Ast.Node.Index, tag: std.zig.Ast.Node.Tag) bool {
    return switch (tag) {
        .@"return" => isBareReturn(ast, source, node),
        .@"break", .@"continue" => true,
        else => false,
    };
}

fn isBareReturn(ast: std.zig.Ast, source: []const u8, node: std.zig.Ast.Node.Index) bool {
    const first = ast.firstToken(node);
    const last = ast.lastToken(node);
    const start = ast.tokenStart(first);
    const end = ast.tokenStart(last) + @as(u32, @intCast(ast.tokenSlice(last).len));
    if (end <= start or end > source.len) return false;

    const snippet = std.mem.trim(u8, source[start..end], " \t\r\n");
    return std.mem.eql(u8, snippet, "return");
}

fn silentExitMessage(kind: FallbackKind) []const u8 {
    return switch (kind) {
        .err_union => "catch branch exits control flow without handling error",
    };
}

fn emptyBlockMessage(kind: FallbackKind) []const u8 {
    return switch (kind) {
        .err_union => "empty catch block suppresses error handling",
    };
}

fn isEmptyBlock(ast: std.zig.Ast, block: std.zig.Ast.Node.Index, source: []const u8) bool {
    const first = ast.firstToken(block);
    const last = ast.lastToken(block);
    const start = ast.tokenStart(first);
    const end = ast.tokenStart(last) + @as(u32, @intCast(ast.tokenSlice(last).len));
    if (end <= start or end > source.len) return false;

    const snippet = source[start..end];
    var i: usize = 0;
    while (i < snippet.len) : (i += 1) {
        const c = snippet[i];
        if (std.ascii.isWhitespace(c) or c == '{' or c == '}') continue;

        if (c == '/' and i + 1 < snippet.len and snippet[i + 1] == '/') {
            i += 2;
            while (i < snippet.len and snippet[i] != '\n') : (i += 1) {}
            continue;
        }
        if (c == '/' and i + 1 < snippet.len and snippet[i + 1] == '*') {
            i += 2;
            while (i + 1 < snippet.len) : (i += 1) {
                if (snippet[i] == '*' and snippet[i + 1] == '/') {
                    i += 1;
                    break;
                }
            }
            continue;
        }

        return false;
    }

    return true;
}

fn isInsideCatchBlock(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) bool {
    const node_first = ast.firstToken(node);
    const node_last = ast.lastToken(node);
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        if (tag != .@"catch") continue;
        const catch_node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (catch_node == node) continue;
        const catch_first = ast.firstToken(catch_node);
        const catch_last = ast.lastToken(catch_node);
        if (catch_first <= node_first and node_last <= catch_last) return true;
    }
    return false;
}

fn checkEmptySwitchElseByAst(ctx: *RuleContext, severity: Severity) !void {
    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        switch (tag) {
            .switch_case, .switch_case_inline, .switch_case_one, .switch_case_inline_one => {},
            else => continue,
        }

        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (ctx.shouldSkipNode(node)) continue;
        const full_case = ast.fullSwitchCase(node) orelse continue;
        if (full_case.ast.values.len != 0) continue;

        const target = full_case.ast.target_expr;
        if (!isEmptyTargetExpr(ast, target)) continue;

        const loc = locations.getNodeLocation(ast, node, ctx.file.content);
        try ctx.addDiagnostic(
            rule_ids.no_silent_error_handling,
            severity,
            loc.line,
            loc.column,
            "empty switch else branch weakens exhaustive handling",
        );
    }
}

fn isEmptyTargetExpr(ast: std.zig.Ast, target: std.zig.Ast.Node.Index) bool {
    const tag = ast.nodeTag(target);
    switch (tag) {
        .block, .block_semicolon, .block_two, .block_two_semicolon => {
            var buf: [2]std.zig.Ast.Node.Index = undefined;
            const statements = ast.blockStatements(&buf, target) orelse return false;
            if (statements.len == 0) return true;

            for (statements) |stmt| {
                if (!isDiscardAssignment(ast, stmt)) return false;
            }
            return true;
        },
        else => return false,
    }
}

fn isDiscardAssignment(ast: std.zig.Ast, stmt: std.zig.Ast.Node.Index) bool {
    if (ast.nodeTag(stmt) != .assign) return false;
    const data = ast.nodeData(stmt);
    const lhs = data.node_and_node[0];
    if (ast.nodeTag(lhs) != .identifier) return false;

    const token = ast.nodes.items(.main_token)[@intFromEnum(lhs)];
    return std.mem.eql(u8, ast.tokenSlice(token), "_");
}

test "detects empty catch block" {
    const source =
        \\fn fallible() anyerror!void {}
        \\fn demo() void {
        \\    _ = fallible() catch {};
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 1);
}

test "detects catch return" {
    const source =
        \\fn fallible() anyerror!void {}
        \\fn demo() void {
        \\    _ = fallible() catch return;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 1);
}

test "does not detect catch return with explicit value" {
    const source =
        \\fn fallible() anyerror!void {}
        \\fn demo() anyerror!usize {
        \\    _ = fallible() catch return 42;
        \\    return 1;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 0);
}

test "detects catch continue" {
    const source =
        \\fn fallible() anyerror!usize { return 1; }
        \\fn demo() void {
        \\    while (true) {
        \\        _ = fallible() catch continue;
        \\        break;
        \\    }
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 1);
}

test "detects catch break" {
    const source =
        \\fn fallible() anyerror!usize { return 1; }
        \\fn demo() void {
        \\    while (true) {
        \\        _ = fallible() catch break;
        \\    }
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 1);
}

test "allows empty catch inside another catch block" {
    const source =
        \\fn foo() anyerror!void {}
        \\fn bar() anyerror!void {}
        \\fn demo() void {
        \\    try foo() catch |err| {
        \\        std.log.err(\"{}\", .{err});
        \\        try bar() catch {};
        \\    };
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 0);
}

fn expectRuleHitsWithAllocator(allocator: std.mem.Allocator, source: []const u8, expected: usize) !void {
    const content = try allocator.dupeZ(u8, source);
    defer allocator.free(content);

    var ast = try std.zig.Ast.parse(allocator, content, .zig);
    defer ast.deinit(allocator);

    const SourceFile = source_file.SourceFile;
    const IgnoreDirectives = ignore_directives.IgnoreDirectives;
    const DiagnosticCollection = diagnostic.DiagnosticCollection;
    const Config = config_zig.Config;

    var file = SourceFile{
        .allocator = allocator,
        .path = "src/sample.zig",
        .content = content,
        .ast = ast,
    };

    var ignores = IgnoreDirectives.init(allocator);
    defer ignores.deinit();

    var diags = DiagnosticCollection.init(allocator);
    defer diags.deinit();

    const config = Config{
        .rules = .{
            .no_silent_error_handling = .{},
        },
    };

    var ctx = RuleContext{
        .allocator = allocator,
        .file = &file,
        .config = config,
        .ignores = &ignores,
        .diagnostics = &diags,
    };

    try run(&ctx);
    try std.testing.expectEqual(expected, diags.items.items.len);
    for (diags.items.items) |diag| {
        try std.testing.expectEqualStrings(rule_ids.no_silent_error_handling, diag.rule_id);
    }
}
