const std = @import("std");
const RuleContext = root.RuleContext;
const Severity = diagnostic.Severity;
const AstUtils = utils.AstUtils;
const rule_ids = @import("../rule_ids.zig");
const root = @import("root.zig");
const diagnostic = @import("../diagnostic.zig");
const utils = @import("utils.zig");
const source_file = @import("../source_file.zig");
const ignore_directives = @import("../ignore_directives.zig");
const config = @import("../config.zig");

/// ZAI006: Detect orelse unreachable patterns
pub fn run(ctx: *RuleContext) !void {
    if (ctx.shouldSkipFile()) return;

    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        if (tag != .@"orelse") continue;

        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (ctx.shouldSkipNode(node)) continue;

        ctx.traceNodeBestEffort(2, node, "inspect");
        const rhs = AstUtils.getRhs(ast, node);
        if (!AstUtils.isNodeTag(ast, rhs, .unreachable_literal)) continue;

        const lhs = AstUtils.getLhs(ast, node);
        const lhs_name = AstUtils.getIdentifierName(ast, lhs);
        if (lhs_name) |name| {
            if (hasPriorNullGuard(ast, node, name)) continue;
        }

        ctx.traceNodeBestEffort(2, node, "match");
        try AstUtils.addDiagnosticAtNode(
            ctx,
            rule_ids.orelse_unreachable,
            Severity.err,
            node,
            "orelse unreachable suppresses null handling - use proper null handling instead",
        );
    }
}

fn hasPriorNullGuard(ast: std.zig.Ast, orelse_node: std.zig.Ast.Node.Index, identifier: []const u8) bool {
    const orelse_first = ast.firstToken(orelse_node);
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        const if_node: std.zig.Ast.Node.Index = @enumFromInt(i);
        const if_last = ast.lastToken(if_node);
        if (if_last >= orelse_first) continue;

        if (tag == .if_simple or tag == .@"if") {
            if (isNullGuardForIdentifier(ast, if_node, tag, identifier)) return true;
        }
    }
    return false;
}

fn isNullGuardForIdentifier(
    ast: std.zig.Ast,
    if_node: std.zig.Ast.Node.Index,
    tag: std.zig.Ast.Node.Tag,
    identifier: []const u8,
) bool {
    const cond = getIfCondition(ast, if_node, tag);

    // Check if condition guards the identifier
    if (conditionGuardsIdentifier(ast, cond, identifier)) {
        const then_expr = getIfThenExpr(ast, if_node, tag);
        if (branchExitsControlFlow(ast, then_expr)) return true;
    }

    // For != null, the else branch is the one that exits
    if (conditionGuardsIdentifierNegated(ast, cond, identifier)) {
        const else_expr = getIfElseExpr(ast, if_node, tag);
        if (branchExitsControlFlow(ast, else_expr)) return true;
    }

    return false;
}

fn getIfCondition(ast: std.zig.Ast, if_node: std.zig.Ast.Node.Index, tag: std.zig.Ast.Node.Tag) std.zig.Ast.Node.Index {
    switch (tag) {
        .if_simple => return ast.nodeData(if_node).node_and_node[0],
        .@"if" => return ast.nodeData(if_node).node_and_extra[0],
        else => unreachable,
    }
}

fn getIfThenExpr(ast: std.zig.Ast, if_node: std.zig.Ast.Node.Index, tag: std.zig.Ast.Node.Tag) std.zig.Ast.Node.Index {
    switch (tag) {
        .if_simple => return ast.nodeData(if_node).node_and_node[1],
        .@"if" => {
            const extra = ast.nodeData(if_node).node_and_extra[1];
            const if_data = ast.extraData(extra, std.zig.Ast.Node.If);
            return if_data.then_expr;
        },
        else => unreachable,
    }
}

fn getIfElseExpr(ast: std.zig.Ast, if_node: std.zig.Ast.Node.Index, tag: std.zig.Ast.Node.Tag) std.zig.Ast.Node.Index {
    switch (tag) {
        .if_simple => return std.zig.Ast.Node.Index.root,
        .@"if" => {
            const extra = ast.nodeData(if_node).node_and_extra[1];
            const if_data = ast.extraData(extra, std.zig.Ast.Node.If);
            return if_data.else_expr;
        },
        else => unreachable,
    }
}

fn conditionGuardsIdentifier(ast: std.zig.Ast, cond: std.zig.Ast.Node.Index, identifier: []const u8) bool {
    const tag = ast.nodeTag(cond);
    switch (tag) {
        .equal_equal => {
            const data = ast.nodeData(cond).node_and_node;
            return isIdentifierAndNull(ast, data[0], data[1], identifier);
        },
        .bool_or => {
            const data = ast.nodeData(cond).node_and_node;
            return conditionGuardsIdentifier(ast, data[0], identifier) or
                conditionGuardsIdentifier(ast, data[1], identifier);
        },
        .bool_and => {
            const data = ast.nodeData(cond).node_and_node;
            return conditionGuardsIdentifier(ast, data[0], identifier) or
                conditionGuardsIdentifier(ast, data[1], identifier);
        },
        else => return false,
    }
}

fn conditionGuardsIdentifierNegated(ast: std.zig.Ast, cond: std.zig.Ast.Node.Index, identifier: []const u8) bool {
    const tag = ast.nodeTag(cond);
    switch (tag) {
        .bang_equal => {
            const data = ast.nodeData(cond).node_and_node;
            return isIdentifierAndNull(ast, data[0], data[1], identifier);
        },
        .bool_and => {
            const data = ast.nodeData(cond).node_and_node;
            return conditionGuardsIdentifierNegated(ast, data[0], identifier) or
                conditionGuardsIdentifierNegated(ast, data[1], identifier);
        },
        else => return false,
    }
}

fn isNull(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) bool {
    const name = AstUtils.getIdentifierName(ast, node) orelse return false;
    return std.mem.eql(u8, name, "null");
}

fn isIdentifierAndNull(
    ast: std.zig.Ast,
    a: std.zig.Ast.Node.Index,
    b: std.zig.Ast.Node.Index,
    identifier: []const u8,
) bool {
    return (isIdentifierName(ast, a, identifier) and isNull(ast, b)) or
        (isIdentifierName(ast, b, identifier) and isNull(ast, a));
}

fn isIdentifierName(ast: std.zig.Ast, node: std.zig.Ast.Node.Index, name: []const u8) bool {
    const n = AstUtils.getIdentifierName(ast, node) orelse return false;
    return std.mem.eql(u8, n, name);
}

fn branchExitsControlFlow(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) bool {
    if (node == std.zig.Ast.Node.Index.root) return false;
    const tag = ast.nodeTag(node);
    switch (tag) {
        .@"return", .@"break", .@"continue", .unreachable_literal => return true,
        .block_two, .block_two_semicolon => {
            const data = ast.nodeData(node).node_and_node;
            return branchExitsControlFlow(ast, data[0]) or branchExitsControlFlow(ast, data[1]);
        },
        .block, .block_semicolon => {
            const range = ast.nodeData(node).extra_range;
            const extra = ast.extra_data[@intFromEnum(range.start)..@intFromEnum(range.end)];
            for (extra) |stmt_idx| {
                const stmt: std.zig.Ast.Node.Index = @enumFromInt(stmt_idx);
                if (branchExitsControlFlow(ast, stmt)) return true;
            }
            return false;
        },
        else => return false,
    }
}

fn expectRuleHitsWithAllocator(allocator: std.mem.Allocator, source: []const u8, expected: usize) !void {
    const content = try allocator.dupeZ(u8, source);
    defer allocator.free(content);

    var ast = try std.zig.Ast.parse(allocator, content, .zig);
    defer ast.deinit(allocator);

    const SourceFile = source_file.SourceFile;
    const IgnoreDirectives = ignore_directives.IgnoreDirectives;
    const DiagnosticCollection = diagnostic.DiagnosticCollection;
    const Config = config.Config;

    var file = SourceFile{
        .allocator = allocator,
        .path = "src/sample.zig",
        .content = content,
        .ast = ast,
    };

    var ignores = try IgnoreDirectives.parse(allocator, source);
    defer ignores.deinit();

    var diagnostics = DiagnosticCollection.init(allocator);
    defer diagnostics.deinit();

    const cfg = Config{
        .rules = .{
            .orelse_unreachable = .{},
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

    try std.testing.expectEqual(expected, diagnostics.items.items.len);
    for (diagnostics.items.items) |diag| {
        try std.testing.expectEqualStrings(rule_ids.orelse_unreachable, diag.rule_id);
        try std.testing.expectEqual(Severity.err, diag.severity);
    }
}

test "detects orelse unreachable" {
    const source =
        \\fn demo(maybe: ?u8) u8 {
        \\    return maybe orelse unreachable;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 1);
}

test "does not detect normal orelse value" {
    const source =
        \\fn demo(maybe: ?u8) u8 {
        \\    return maybe orelse 0;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 0);
}

test "skips when null guard with return exists" {
    const source =
        \\fn demo(maybe: ?u8) u8 {
        \\    if (maybe == null) return 0;
        \\    return maybe orelse unreachable;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 0);
}

test "skips when null guard with break exists" {
    const source =
        \\fn demo(list: std.ArrayList(?u8)) void {
        \\    for (list.items) |maybe| {
        \\        if (maybe == null) break;
        \\        _ = maybe orelse unreachable;
        \\    }
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 0);
}

test "skips when negated null guard with else return exists" {
    const source =
        \\fn demo(maybe: ?u8) u8 {
        \\    if (maybe != null) {}
        \\    else return 0;
        \\    return maybe orelse unreachable;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 0);
}

test "skips when compound null guard with return exists" {
    const source =
        \\fn demo(a: ?u8, b: ?u8) void {
        \\    if (a == null or b == null) return;
        \\    _ = a orelse unreachable;
        \\    _ = b orelse unreachable;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 0);
}
