const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");

const ParamInfo = struct {
    name: []const u8,
    node: std.zig.Ast.Node.Index,
};

/// ZAI006: Detect allocator parameter passed but not used
/// This catches the pattern: fn foo(allocator: Allocator) void { _ = allocator; }
pub fn run(ctx: *RuleContext) !void {
    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    // Find all function declarations
    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);

        switch (tag) {
            .fn_decl => {
                try checkFunction(ctx, node);
            },
            else => {},
        }
    }
}

fn checkFunction(ctx: *RuleContext, fn_node: std.zig.Ast.Node.Index) !void {
    const ast = ctx.file.ast;

    // Get function prototype to find parameters
    const fn_data = ast.nodeData(fn_node);
    const proto_node = fn_data.node_and_node[0];

    // Get parameter list from prototype - use fullFnProto
    var buf: [1]std.zig.Ast.Node.Index = undefined;
    if (ast.fullFnProto(&buf, proto_node)) |proto| {
        const params = proto.ast.params;

        // Check for allocator parameters
        var params_to_check = std.ArrayList(ParamInfo).empty;
        defer params_to_check.deinit(ctx.allocator);

        for (params) |param| {
            try checkParamForAllocator(ast, param, ctx.allocator, &params_to_check);
        }

        // Check if any allocator parameter is used
        for (params_to_check.items) |param| {
            if (!isParamUsed(ast, fn_node, param.name)) {
                const loc = locations.getNodeLocation(ast, fn_node, ctx.file.content);
                try ctx.addDiagnostic(
                    "ZAI006",
                    Severity.err,
                    loc.line,
                    loc.column,
                    "allocator parameter is passed but never used",
                );
            }
        }
    }
}

fn checkParamForAllocator(ast: std.zig.Ast, param_node: std.zig.Ast.Node.Index, gpa: std.mem.Allocator, list: *std.ArrayList(ParamInfo)) !void {
    // Get parameter name from first token
    const tokens = ast.nodes.items(.main_token);
    const tok = tokens[@intFromEnum(param_node)];
    const name = ast.tokenSlice(tok);

    // Check if name suggests allocator
    if (isAllocatorName(name)) {
        try list.append(gpa, .{ .name = name, .node = param_node });
    }
}

fn isAllocatorName(name: []const u8) bool {
    return std.mem.eql(u8, name, "allocator") or
        std.mem.eql(u8, name, "alloc") or
        std.mem.eql(u8, name, "gpa") or
        std.mem.eql(u8, name, "arena") or
        std.mem.endsWith(u8, name, "_allocator") or
        std.mem.endsWith(u8, name, "_alloc");
}

fn isParamUsed(ast: std.zig.Ast, fn_node: std.zig.Ast.Node.Index, param_name: []const u8) bool {
    // Get function body
    const body = ast.nodeData(fn_node).node_and_node[1];

    // Simple check: look for identifier with this name in function body
    return checkIdentifierUsage(ast, body, param_name);
}

fn checkIdentifierUsage(ast: std.zig.Ast, node: std.zig.Ast.Node.Index, name: []const u8) bool {
    const tags = ast.nodes.items(.tag);
    const tag = tags[@intFromEnum(node)];

    // Check if this node is an identifier with matching name
    if (tag == .identifier) {
        const tokens = ast.nodes.items(.main_token);
        const tok = tokens[@intFromEnum(node)];
        const node_name = ast.tokenSlice(tok);

        if (std.mem.eql(u8, node_name, name)) {
            return true;
        }
    }

    // TODO: Recurse into child nodes
    // For now, we do a simple check that catches obvious cases

    return false;
}
