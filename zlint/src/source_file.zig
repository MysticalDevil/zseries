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

    /// Check if a node is inside a test block
    /// Complete implementation: checks if target is descendant of any test_decl
    pub fn isInsideTestBlock(self: SourceFile, target: std.zig.Ast.Node.Index) bool {
        const ast = self.ast;
        const tags = ast.nodes.items(.tag);

        // Find all test_decl nodes and check if target is in their subtree
        for (tags, 0..) |tag, i| {
            if (tag == .test_decl) {
                const test_node: std.zig.Ast.Node.Index = @enumFromInt(i);
                if (self.isNodeDescendantOf(test_node, target)) {
                    return true;
                }
            }
        }

        return false;
    }

    /// Check if target is descendant of ancestor (including direct children check)
    fn isNodeDescendantOf(self: SourceFile, ancestor: std.zig.Ast.Node.Index, target: std.zig.Ast.Node.Index) bool {
        if (ancestor == target) return false;

        const ast = self.ast;

        // Get ancestor's first and last token
        const anc_first = ast.firstToken(ancestor);
        const anc_last = ast.lastToken(ancestor);

        // Get target's first and last token
        const tgt_first = ast.firstToken(target);
        const tgt_last = ast.lastToken(target);

        // Check if target is within ancestor's token range
        if (tgt_first >= anc_first and tgt_last <= anc_last) {
            return true;
        }

        return false;
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
