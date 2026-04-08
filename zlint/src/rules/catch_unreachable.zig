const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const AstUtils = @import("utils.zig").AstUtils;
const rule_ids = @import("../rule_ids.zig");

/// ZAI004: Detect catch unreachable / orelse unreachable / .? patterns
pub fn run(ctx: *RuleContext) !void {
    if (ctx.shouldSkipFile()) return;

    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);

        if (ctx.shouldSkipNode(node)) continue;

        if (tag == .@"catch" or tag == .@"orelse") {
            ctx.traceNodeBestEffort(2, node, "inspect");
            const rhs = AstUtils.getRhs(ast, node);
            if (AstUtils.isNodeTag(ast, rhs, .unreachable_literal)) {
                ctx.traceNodeBestEffort(2, node, "match");
                const msg = if (tag == .@"catch")
                    "catch unreachable suppresses error handling - use proper error handling instead"
                else
                    "orelse unreachable suppresses null handling - use proper null handling instead";
                try AstUtils.addDiagnosticAtNode(ctx, rule_ids.catch_unreachable, Severity.err, node, msg);
            }
        } else if (tag == .unwrap_optional) {
            ctx.traceNodeBestEffort(2, node, "match");
            try AstUtils.addDiagnosticAtNode(
                ctx,
                rule_ids.catch_unreachable,
                Severity.warning,
                node,
                "optional unwrap (.?) may panic - consider explicit null handling with orelse",
            );
        }
    }
}
