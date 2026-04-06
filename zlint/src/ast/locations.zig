const std = @import("std");

pub const Location = struct {
    line: usize,
    column: usize,
};

/// Get line and column from token index
pub fn getTokenLocation(ast: std.zig.Ast, token_idx: std.zig.Ast.TokenIndex, source: []const u8) Location {
    const start = ast.tokens.items(.start)[token_idx];

    var line: usize = 1;
    var column: usize = 1;

    for (source[0..@min(start, source.len)]) |c| {
        if (c == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }

    return .{ .line = line, .column = column };
}

/// Get line and column from node
pub fn getNodeLocation(ast: std.zig.Ast, node: std.zig.Ast.Node.Index, source: []const u8) Location {
    const tokens = ast.nodes.items(.main_token);
    const token = tokens[@intFromEnum(node)];
    return getTokenLocation(ast, token, source);
}
