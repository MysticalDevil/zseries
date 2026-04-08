const std = @import("std");

const Tag = std.zig.Ast.Node.Tag;
const Index = std.zig.Ast.Node.Index;

/// Result of traversing one step in field access chain
const StepResult = enum {
    field,
    identifier,
    other,
};

/// Get the next step in field access chain
fn nextFieldAccessStep(
    ast: std.zig.Ast,
    current: Index,
    out_lhs: *Index,
    out_token: *std.zig.Ast.TokenIndex,
) StepResult {
    const tags = ast.nodes.items(.tag);
    const tag = tags[@intFromEnum(current)];

    switch (tag) {
        .field_access => {
            const data = ast.nodeData(current);
            out_lhs.* = data.node_and_token[0];
            out_token.* = data.node_and_token[1];
            return .field;
        },
        .identifier => {
            const tokens = ast.nodes.items(.main_token);
            out_token.* = tokens[@intFromEnum(current)];
            return .identifier;
        },
        else => return .other,
    }
}

/// Extract the full dotted path from a field access chain
pub fn extractPath(ast: std.zig.Ast, node: Index, buf: *std.ArrayList(u8), gpa: std.mem.Allocator) !?[]const u8 {
    buf.clearRetainingCapacity();

    var current = node;
    var first = true;
    var lhs: Index = undefined;
    var token: std.zig.Ast.TokenIndex = undefined;

    while (true) {
        switch (nextFieldAccessStep(ast, current, &lhs, &token)) {
            .field => {
                const field_name = ast.tokenSlice(token);
                if (!first) try buf.insert(gpa, 0, '.');
                try buf.insertSlice(gpa, 0, field_name);
                first = false;
                current = lhs;
            },
            .identifier => {
                const name = ast.tokenSlice(token);
                if (!first) try buf.insert(gpa, 0, '.');
                try buf.insertSlice(gpa, 0, name);
                return try gpa.dupe(u8, buf.items);
            },
            .other => return null,
        }
    }
}

/// Get the base identifier from a field access chain
pub fn getBaseIdentifier(ast: std.zig.Ast, node: Index) ?[]const u8 {
    var current = node;
    var lhs: Index = undefined;
    var token: std.zig.Ast.TokenIndex = undefined;

    while (true) {
        switch (nextFieldAccessStep(ast, current, &lhs, &token)) {
            .field => current = lhs,
            .identifier => return ast.tokenSlice(token),
            .other => return null,
        }
    }
}
