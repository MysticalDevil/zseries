const std = @import("std");

/// Represents a source file with its content and AST
pub const SourceFile = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    content: [:0]const u8,
    ast: std.zig.Ast,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !SourceFile {
        const cwd = std.Io.Dir.cwd();

        // Read file content
        const content = cwd.readFileAlloc(io, path, allocator, .unlimited) catch |err| {
            return err;
        };

        // Ensure content is sentinel-terminated for Ast.parse
        const content_z = try allocator.dupeZ(u8, content);
        allocator.free(content);

        const ast = try std.zig.Ast.parse(allocator, content_z, .zig);

        return .{
            .allocator = allocator,
            .path = path,
            .content = content_z,
            .ast = ast,
        };
    }

    pub fn deinit(self: *SourceFile) void {
        self.ast.deinit(self.allocator);
        self.allocator.free(self.content);
    }

    /// Check if this file is a test file based on path patterns
    pub fn isTestFile(self: SourceFile) bool {
        const path = self.path;

        // Check file name patterns
        if (std.mem.endsWith(u8, path, "_test.zig")) return true;
        if (std.mem.indexOf(u8, path, "/test/") != null) return true;
        if (std.mem.indexOf(u8, path, "/tests/") != null) return true;

        // Check for test.zig or main_test.zig patterns
        const basename = std.fs.path.basename(path);
        if (std.mem.eql(u8, basename, "test.zig")) return true;

        return false;
    }

    /// Check if a node is inside a test block by scanning for test_decl
    pub fn isInsideTestBlock(self: SourceFile, node: std.zig.Ast.Node.Index) bool {
        const ast = self.ast;
        const tags = ast.nodes.items(.tag);
        const node_idx = @intFromEnum(node);

        // Find the first test_decl before this node
        for (tags[0..node_idx], 0..) |tag, test_idx| {
            if (tag == .test_decl) {
                // Check if our node is within the scope of this test
                const test_node: std.zig.Ast.Node.Index = @enumFromInt(test_idx);
                if (self.isNodeInScope(test_node, node)) {
                    return true;
                }
            }
        }

        return false;
    }

    /// Check if child node is within parent node's scope
    fn isNodeInScope(self: SourceFile, parent: std.zig.Ast.Node.Index, child: std.zig.Ast.Node.Index) bool {
        const parent_idx = @intFromEnum(parent);
        const child_idx = @intFromEnum(child);

        // Simple heuristic: if child comes after parent and they're in the same file,
        // and there's no other top-level declaration between them
        if (child_idx <= parent_idx) return false;

        const ast = self.ast;
        const tags = ast.nodes.items(.tag);

        // Check if there's another top-level decl between parent and child
        var idx = parent_idx + 1;
        while (idx < child_idx) : (idx += 1) {
            const tag = tags[idx];
            switch (tag) {
                .fn_decl, .global_var_decl, .local_var_decl, .test_decl => {
                    // Found another top-level item
                    return false;
                },
                else => {},
            }
        }

        return true;
    }

    /// Get line and column from byte offset
    pub fn getLineColumn(self: SourceFile, offset: usize) struct { line: usize, column: usize } {
        var line: usize = 1;
        var column: usize = 1;

        for (self.content[0..@min(offset, self.content.len)]) |c| {
            if (c == '\n') {
                line += 1;
                column = 1;
            } else {
                column += 1;
            }
        }

        return .{ .line = line, .column = column };
    }
};
