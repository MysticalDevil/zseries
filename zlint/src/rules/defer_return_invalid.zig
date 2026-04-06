const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");

/// ZAI005: Detect returning resources after defer deinit
/// This catches the pattern: defer list.deinit(); return list.items;
pub fn run(ctx: *RuleContext) !void {
    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    // Find all function declarations
    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);

        // Only check fn_decl which has a body
        if (tag == .fn_decl) {
            try checkFunction(ctx, node);
        }
    }
}

fn checkFunction(ctx: *RuleContext, fn_node: std.zig.Ast.Node.Index) !void {
    const ast = ctx.file.ast;

    // Get function body - fn_decl uses node_and_node: { proto, body }
    const fn_data = ast.nodeData(fn_node);
    const body = fn_data.node_and_node[1];

    // Collect all defer statements in this function
    var defers = std.ArrayList(std.zig.Ast.Node.Index).empty;
    defer defers.deinit(ctx.allocator);

    try collectDefers(ast, body, ctx.allocator, &defers);

    if (defers.items.len == 0) return;

    // Check return statements
    try checkReturns(ctx, ast, body, defers.items);
}

fn collectDefers(ast: std.zig.Ast, node: std.zig.Ast.Node.Index, allocator: std.mem.Allocator, defers: *std.ArrayList(std.zig.Ast.Node.Index)) !void {
    const tags = ast.nodes.items(.tag);
    const tag = tags[@intFromEnum(node)];

    if (tag == .@"defer" or tag == .@"errdefer") {
        try defers.append(allocator, node);
        return;
    }

    // Recurse into block-like nodes
    switch (tag) {
        .block_two, .block_two_semicolon, .block, .block_semicolon => {
            // Get statements in block
            // For simplicity, we just check if node has defer children
            // Full implementation would need to iterate block statements
        },
        else => {},
    }
}

fn checkReturns(ctx: *RuleContext, ast: std.zig.Ast, body: std.zig.Ast.Node.Index, defers: []const std.zig.Ast.Node.Index) !void {
    _ = body;
    _ = defers;
    const tags = ast.nodes.items(.tag);

    // Find return statements
    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);

        if (tag == .@"return") {
            const return_data = ast.nodeData(node);
            // Check if opt_node is not none (has return expression)
            if (@intFromEnum(return_data.opt_node) == 0) continue;

            const return_expr = return_data.opt_node.unwrap() orelse continue;

            // Check if return expression involves ArrayList.items or similar
            if (isSuspiciousReturn(ast, return_expr)) {
                const loc = locations.getNodeLocation(ast, node, ctx.file.content);
                try ctx.addDiagnostic(
                    "ZAI005",
                    Severity.err,
                    loc.line,
                    loc.column,
                    "returning potentially invalid resource after defer - ensure resource outlives return",
                );
            }
        }
    }
}

fn isSuspiciousReturn(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) bool {
    const tags = ast.nodes.items(.tag);
    const tag = tags[@intFromEnum(node)];

    switch (tag) {
        .field_access => {
            // Check for .items access
            const tokens = ast.nodes.items(.main_token);
            const main_tok = tokens[@intFromEnum(node)];
            const field_name = ast.tokenSlice(main_tok + 1);

            if (std.mem.eql(u8, field_name, "items") or
                std.mem.eql(u8, field_name, "slice") or
                std.mem.eql(u8, field_name, "buffer"))
            {
                return true;
            }
        },
        else => {},
    }

    return false;
}
