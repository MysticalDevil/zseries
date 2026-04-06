const std = @import("std");

/// Extract the full dotted path from a field access chain
pub fn extractPath(ast: std.zig.Ast, node: std.zig.Ast.Node.Index, buf: *std.ArrayList(u8), gpa: std.mem.Allocator) !?[]const u8 {
    buf.clearRetainingCapacity();

    var current = node;
    var first = true;

    while (true) {
        const tags = ast.nodes.items(.tag);
        const tokens = ast.nodes.items(.main_token);
        const node_idx = @intFromEnum(current);
        const tag = tags[node_idx];

        switch (tag) {
            .field_access => {
                const data = ast.nodeData(current);
                const lhs = data.node_and_token[0];
                const field_token = data.node_and_token[1];
                const field_name = ast.tokenSlice(field_token);

                if (!first) {
                    try buf.insert(gpa, 0, '.');
                }
                try buf.insertSlice(gpa, 0, field_name);
                first = false;

                current = lhs;
            },
            .identifier => {
                const token = tokens[node_idx];
                const name = ast.tokenSlice(token);
                if (!first) {
                    try buf.insert(gpa, 0, '.');
                }
                try buf.insertSlice(gpa, 0, name);
                break;
            },
            else => return null,
        }
    }

    return buf.items;
}

/// Get the base identifier from a field access chain
pub fn getBaseIdentifier(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) ?[]const u8 {
    var current = node;

    while (true) {
        const tags = ast.nodes.items(.tag);
        const tokens = ast.nodes.items(.main_token);
        const node_idx = @intFromEnum(current);
        const tag = tags[node_idx];

        switch (tag) {
            .field_access => {
                const data = ast.nodeData(current);
                current = data.node_and_token[0];
            },
            .identifier => {
                const token = tokens[node_idx];
                return ast.tokenSlice(token);
            },
            else => return null,
        }
    }
}
