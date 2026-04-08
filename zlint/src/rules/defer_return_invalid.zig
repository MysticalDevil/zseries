const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");
const rule_ids = @import("../rule_ids.zig");

/// ZAI005: Detect returning resources after defer deinit
pub fn run(ctx: *RuleContext) !void {
    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);
    var severity = Severity.err;
    if (ctx.config.rules.defer_return_invalid) |cfg| {
        severity = Severity.fromString(cfg.base.severity) orelse Severity.err;
    }

    for (tags, 0..) |tag, i| {
        if (tag != .@"return") continue;

        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        const return_data = ast.nodeData(node);

        // Skip if no return expression
        if (@intFromEnum(return_data.opt_node) == 0) continue;
        const return_expr = return_data.opt_node.unwrap() orelse continue;

        // Check if return involves .items/.slice/.buffer field access
        if (isResourceFieldAccess(ast, return_expr)) {
            const loc = locations.getNodeLocation(ast, node, ctx.file.content);
            try ctx.addDiagnostic(
                rule_ids.defer_return_invalid,
                severity,
                loc.line,
                loc.column,
                "returning potentially invalid resource after defer - ensure resource outlives return",
            );
        }
    }
}

fn isResourceFieldAccess(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) bool {
    if (ast.nodeTag(node) != .field_access) return false;

    const tokens = ast.nodes.items(.main_token);
    const main_tok = tokens[@intFromEnum(node)];
    const field_name = ast.tokenSlice(main_tok + 1);

    return std.mem.eql(u8, field_name, "items") or
        std.mem.eql(u8, field_name, "slice") or
        std.mem.eql(u8, field_name, "buffer");
}
