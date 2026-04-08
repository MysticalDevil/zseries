const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");
const rule_ids = @import("../rule_ids.zig");

pub fn run(ctx: *RuleContext) !void {
    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    var severity = Severity.warning;
    if (ctx.config.rules.no_empty_block) |cfg| {
        severity = Severity.fromString(cfg.base.severity) orelse Severity.warning;
    }

    for (tags, 0..) |tag, i| {
        if (tag != .@"catch") continue;
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        try checkCatchBlock(ctx, node, severity);
    }

    try checkEmptySwitchElseByAst(ctx, severity);
}

fn checkCatchBlock(ctx: *RuleContext, node: std.zig.Ast.Node.Index, severity: Severity) !void {
    const ast = ctx.file.ast;
    const rhs = ast.nodeData(node).node_and_node[1];
    const rhs_tag = ast.nodeTag(rhs);

    if (rhs_tag == .unreachable_literal) return;
    if (rhs_tag == .identifier) {
        const token = ast.nodes.items(.main_token)[@intFromEnum(rhs)];
        if (std.mem.eql(u8, ast.tokenSlice(token), "null")) return;
    }

    if (rhs_tag == .block or rhs_tag == .block_semicolon or rhs_tag == .block_two or rhs_tag == .block_two_semicolon) {
        if (isEmptyBlock(ast, rhs, ctx.file.content)) {
            const loc = locations.getNodeLocation(ast, node, ctx.file.content);
            try ctx.addDiagnostic(
                rule_ids.no_empty_block,
                severity,
                loc.line,
                loc.column,
                "empty catch block suppresses error handling",
            );
        }
    }
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

fn checkEmptySwitchElseByAst(ctx: *RuleContext, severity: Severity) !void {
    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        switch (tag) {
            .switch_case, .switch_case_inline, .switch_case_one, .switch_case_inline_one => {},
            else => continue,
        }

        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        const full_case = ast.fullSwitchCase(node) orelse continue;
        if (full_case.ast.values.len != 0) continue;

        const target = full_case.ast.target_expr;
        if (!isEmptyTargetExpr(ast, target)) continue;

        const loc = locations.getNodeLocation(ast, node, ctx.file.content);
        try ctx.addDiagnostic(
            rule_ids.no_empty_block,
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
