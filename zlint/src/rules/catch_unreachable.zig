const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");

/// ZAI004: Detect catch unreachable / orelse unreachable / .? patterns
/// These are common AI patterns to suppress error handling
pub fn run(ctx: *RuleContext) !void {
    // Skip test files if configured
    if (ctx.shouldSkipFile()) return;

    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);

        // Skip nodes inside test blocks if configured
        if (ctx.shouldSkipNode(node)) continue;

        if (tag == .@"catch") {
            try checkCatch(ctx, node);
        } else if (tag == .@"orelse") {
            try checkOrElse(ctx, node);
        } else if (tag == .unwrap_optional) {
            try checkUnwrap(ctx, node);
        }
    }
}

fn checkCatch(ctx: *RuleContext, node: std.zig.Ast.Node.Index) !void {
    const ast = ctx.file.ast;
    const node_data = ast.nodeData(node);

    // catch uses node_and_node: { lhs, rhs }
    const rhs = node_data.node_and_node[1];

    // Check if rhs is unreachable
    if (ast.nodeTag(rhs) == .unreachable_literal) {
        const loc = locations.getNodeLocation(ast, node, ctx.file.content);
        try ctx.addDiagnostic(
            "catch-unreachable",
            Severity.err,
            loc.line,
            loc.column,
            "catch unreachable suppresses error handling - use proper error handling instead",
        );
    }
}

fn checkOrElse(ctx: *RuleContext, node: std.zig.Ast.Node.Index) !void {
    const ast = ctx.file.ast;
    const node_data = ast.nodeData(node);

    // orelse uses node_and_node: { lhs, rhs }
    const rhs = node_data.node_and_node[1];

    // Check if rhs is unreachable
    if (ast.nodeTag(rhs) == .unreachable_literal) {
        const loc = locations.getNodeLocation(ast, node, ctx.file.content);
        try ctx.addDiagnostic(
            "catch-unreachable",
            Severity.err,
            loc.line,
            loc.column,
            "orelse unreachable suppresses null handling - use proper null handling instead",
        );
    }
}

fn checkUnwrap(ctx: *RuleContext, node: std.zig.Ast.Node.Index) !void {
    const ast = ctx.file.ast;
    const loc = locations.getNodeLocation(ast, node, ctx.file.content);

    try ctx.addDiagnostic(
        "ZAI004",
        Severity.warning,
        loc.line,
        loc.column,
        "optional unwrap (.?) may panic - consider explicit null handling with orelse",
    );
}
