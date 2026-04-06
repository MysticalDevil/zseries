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
