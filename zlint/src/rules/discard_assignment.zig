const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");
const rule_ids = @import("../rule_ids.zig");

pub fn run(ctx: *RuleContext) !void {
    if (ctx.shouldSkipFile()) return;

    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    var severity = Severity.warning;
    if (ctx.config.rules.discard_assignment) |cfg| {
        severity = Severity.fromString(cfg.base.severity) orelse Severity.warning;
    }

    for (tags, 0..) |tag, i| {
        if (tag != .assign) continue;

        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (ctx.shouldSkipNode(node)) continue;
        const lhs = ast.nodeData(node).node_and_node[0];
        if (!isUnderscore(ast, lhs)) continue;

        const loc = locations.getNodeLocation(ast, node, ctx.file.content);
        try ctx.addDiagnostic(
            rule_ids.discard_assignment,
            severity,
            loc.line,
            loc.column,
            "explicit discard assignment '_ = ...;' detected",
        );
    }
}

fn isUnderscore(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) bool {
    if (ast.nodeTag(node) != .identifier) return false;
    const tok = ast.nodes.items(.main_token)[@intFromEnum(node)];
    return std.mem.eql(u8, ast.tokenSlice(tok), "_");
}
