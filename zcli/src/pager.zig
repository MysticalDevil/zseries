const std = @import("std");

pub fn pager(writer: *std.Io.Writer, content: []const u8, lines_per_page: usize) !void {
    if (lines_per_page == 0) {
        try writer.writeAll(content);
        return;
    }

    var line_count: usize = 0;
    var pos: usize = 0;

    while (pos < content.len) {
        const newline_pos = std.mem.indexOfScalarPos(u8, content, pos, '\n') orelse content.len;
        const line = content[pos..newline_pos];
        try writer.writeAll(line);
        try writer.writeAll("\n");
        line_count += 1;
        pos = newline_pos + 1;

        if (line_count >= lines_per_page and pos < content.len) {
            try writer.writeAll("-- More --");
            var buf: [16]u8 = undefined;
            const stdin = std.Io.File.stdin();
            var reader = stdin.reader(std.Io.Threaded.init_single_threaded, &buf);
            const input = (try reader.interface.takeDelimiter('\n')) orelse "";
            if (input.len > 0 and (input[0] == 'q' or input[0] == 'Q')) {
                return;
            }
            try writer.writeAll("\r          \r");
            line_count = 0;
        }
    }
}

pub const PagerEnv = struct {
    lines: usize = 24,
    cols: usize = 80,
};

pub fn detectPagerEnv(env: *const std.process.Environ.Map) PagerEnv {
    var result: PagerEnv = .{};

    if (env.get("LINES")) |lines| {
        result.lines = std.fmt.parseInt(usize, lines, 10) catch 24;
    }
    if (env.get("COLUMNS")) |cols| {
        result.cols = std.fmt.parseInt(usize, cols, 10) catch 80;
    }

    return result;
}

pub fn withPagerAlloc(allocator: std.mem.Allocator, content: []const u8, env: *const std.process.Environ.Map) ![]u8 {
    const pager_env = detectPagerEnv(env);
    var buf: std.Io.Writer.Allocating = .init(allocator);
    defer buf.deinit();
    try pager(&buf.writer, content, pager_env.lines);
    return buf.toOwnedSlice();
}

test "pager outputs all content when lines_per_page is zero" {
    const testing = std.testing;
    var buf: std.Io.Writer.Allocating = .init(testing.allocator);
    defer buf.deinit();
    const content = "line1\nline2\nline3\n";
    try pager(&buf.writer, content, 0);
    const text = try buf.toOwnedSlice();
    defer testing.allocator.free(text);
    try testing.expectEqualStrings(content, text);
}
