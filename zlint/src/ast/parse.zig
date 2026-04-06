const std = @import("std");

/// Parse Zig source into AST
pub fn parse(allocator: std.mem.Allocator, source: []const u8) !std.zig.Ast {
    return try std.zig.Ast.parse(allocator, source, .zig);
}

/// Get the source text for a node
pub fn getNodeSource(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) []const u8 {
    const tokens = ast.nodes.items(.main_token);
    const token = tokens[node];
    return ast.tokenSlice(token);
}

/// Check if a node is of a specific type
pub fn isNodeType(ast: std.zig.Ast, node: std.zig.Ast.Node.Index, tag: std.zig.Ast.Node.Tag) bool {
    return ast.nodes.items(.tag)[node] == tag;
}
