const std = @import("std");
const zcli = @import("zcli");
const Diagnostic = @import("../diagnostic.zig").Diagnostic;
const Summary = @import("../diagnostic.zig").Summary;

const ICON_ERROR = "[X]";
const ICON_WARNING = "[!]";
const ICON_HELP = "[?]";

pub const Options = struct {
    use_color: bool = true,
    collapse_duplicates: bool = true,
    max_per_group: usize = 3,
    context_lines: usize = 1,
};

pub fn writeText(
    allocator: std.mem.Allocator,
    io: std.Io,
    writer: *std.Io.Writer,
    diagnostics: []const Diagnostic,
    summary: Summary,
    opts: Options,
) !void {
    if (diagnostics.len == 0) {
        try writeSummary(writer, summary, opts.use_color);
        return;
    }

    const sorted = try allocator.alloc(Diagnostic, diagnostics.len);
    defer allocator.free(sorted);
    @memcpy(sorted, diagnostics);
    std.sort.pdq(Diagnostic, sorted, {}, lessDiagnostic);

    var file_cache = FileCache.init(allocator);
    defer file_cache.deinit();

    var i: usize = 0;
    var current_path: ?[]const u8 = null;
    while (i < sorted.len) {
        const d = sorted[i];

        const same_path = if (current_path) |cp| std.mem.eql(u8, cp, d.path) else false;
        if (!same_path) {
            if (current_path != null) try writer.writeByte('\n');
            try zcli.color.writeStyled(writer, opts.use_color, .muted, "-- ");
            try writeNormalizedPath(writer, d.path);
            try zcli.color.writeStyled(writer, opts.use_color, .muted, " --");
            try writer.writeByte('\n');
            current_path = d.path;
        }

        var j = i + 1;
        while (j < sorted.len and sameGroup(sorted[i], sorted[j])) : (j += 1) {}

        const group_len = j - i;
        const shown = if (opts.collapse_duplicates) @min(group_len, opts.max_per_group) else group_len;

        for (i..i + shown) |idx| {
            const item = sorted[idx];
            const content = try file_cache.get(io, item.path);
            try writeDiagnostic(writer, item, content, opts);
        }

        if (shown < group_len) {
            const hidden = group_len - shown;
            try writer.writeAll("  note: ");
            var buf: [96]u8 = undefined;
            const text = try std.fmt.bufPrint(&buf, "+{d} more similar diagnostics hidden", .{hidden});
            try zcli.color.writeStyled(writer, opts.use_color, .muted, text);
            try writer.writeByte('\n');
        }

        i = j;
    }

    try writer.writeByte('\n');
    try writeSummary(writer, summary, opts.use_color);
}

fn lessDiagnostic(_: void, a: Diagnostic, b: Diagnostic) bool {
    return cmpDiagnostic(a, b) == .lt;
}

fn cmpDiagnostic(a: Diagnostic, b: Diagnostic) std.math.Order {
    const path_order = std.mem.order(u8, a.path, b.path);
    if (path_order != .eq) return path_order;

    const rule_order = std.mem.order(u8, a.rule_id, b.rule_id);
    if (rule_order != .eq) return rule_order;

    const severity_order = std.mem.order(u8, a.severity.toString(), b.severity.toString());
    if (severity_order != .eq) return severity_order;

    const msg_order = std.mem.order(u8, a.message, b.message);
    if (msg_order != .eq) return msg_order;

    if (a.line < b.line) return .lt;
    if (a.line > b.line) return .gt;
    if (a.column < b.column) return .lt;
    if (a.column > b.column) return .gt;
    return .eq;
}

fn sameGroup(a: Diagnostic, b: Diagnostic) bool {
    return std.mem.eql(u8, a.path, b.path) and
        std.mem.eql(u8, a.rule_id, b.rule_id) and
        a.severity == b.severity and
        std.mem.eql(u8, a.message, b.message);
}

fn writeDiagnostic(writer: *std.Io.Writer, d: Diagnostic, file_content: ?[]const u8, opts: Options) !void {
    const style: zcli.color.Style = switch (d.severity) {
        .err => .title,
        .warning => .flag,
        .help => .muted,
    };
    const icon = switch (d.severity) {
        .err => ICON_ERROR,
        .warning => ICON_WARNING,
        .help => ICON_HELP,
    };
    const sev_text = d.severity.toString();

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, opts.use_color, style, icon);
    try writer.writeByte(' ');
    try zcli.color.writeStyled(writer, opts.use_color, style, sev_text);
    try writer.writeByte('[');
    try zcli.color.writeStyled(writer, opts.use_color, .value, d.rule_id);
    try writer.writeAll("]: ");
    try writer.writeAll(d.message);
    try writer.writeByte('\n');

    try writer.writeAll("     --> ");
    try writeNormalizedPath(writer, d.path);
    try writer.print(":{d}:{d}\n", .{ d.line, d.column });

    if (file_content) |content| {
        try writeSnippet(writer, content, d.line, d.column, opts);
    }
}

fn writeSnippet(writer: *std.Io.Writer, content: []const u8, target_line: usize, target_col: usize, opts: Options) !void {
    const start_line = if (target_line > opts.context_lines) target_line - opts.context_lines else 1;
    const end_line = target_line + opts.context_lines;

    try zcli.color.writeStyled(writer, opts.use_color, .muted, "      |\n");

    var iter = std.mem.splitScalar(u8, content, '\n');
    var line_no: usize = 1;
    while (iter.next()) |line| : (line_no += 1) {
        if (line_no < start_line) continue;
        if (line_no > end_line) break;

        try writer.print("{d: >5} ", .{line_no});
        try zcli.color.writeStyled(writer, opts.use_color, .muted, "|");
        try writer.writeByte(' ');
        try writer.writeAll(line);
        try writer.writeByte('\n');

        if (line_no == target_line) {
            try writer.writeAll("      ");
            try zcli.color.writeStyled(writer, opts.use_color, .muted, "|");
            try writer.writeByte(' ');
            const caret = visualColumnOffset(line, target_col);
            for (0..caret) |_| try writer.writeByte(' ');
            try zcli.color.writeStyled(writer, opts.use_color, .flag, "^");
            try writer.writeByte('\n');
        }
    }
}

fn visualColumnOffset(line: []const u8, col_1based: usize) usize {
    if (col_1based <= 1) return 0;
    const wanted = col_1based - 1;
    const take = @min(wanted, line.len);

    var visual: usize = 0;
    for (line[0..take]) |c| {
        if (c == '\t') {
            visual += 4 - (visual % 4);
        } else {
            visual += 1;
        }
    }
    return visual;
}

fn writeSummary(writer: *std.Io.Writer, s: Summary, use_color: bool) !void {
    try zcli.color.writeStyled(writer, use_color, .heading, "==============================\n");
    try zcli.color.writeStyled(writer, use_color, .heading, "Summary\n");
    try writer.print("  files: {d}\n", .{s.files_scanned});
    try writer.print("  diagnostics: {d}\n", .{s.diagnostics});
    try writer.print("  errors: {d}\n", .{s.errors});
    try writer.print("  warnings: {d}\n", .{s.warnings});
    try writer.print("  helps: {d}\n", .{s.helps});
    if (s.errors > 0) {
        try zcli.color.writeStyled(writer, use_color, .title, "  status: failed\n");
    } else {
        try zcli.color.writeStyled(writer, use_color, .command, "  status: ok\n");
    }
}

fn writeNormalizedPath(writer: *std.Io.Writer, path: []const u8) !void {
    var i: usize = 0;
    while (i + 1 < path.len and path[i] == '.' and path[i + 1] == '/') : (i += 2) {}

    var wrote_any = false;
    while (i < path.len) {
        if (path[i] == '/' and i + 1 < path.len and path[i + 1] == '/') {
            i += 1;
            continue;
        }

        if (path[i] == '/' and i + 1 < path.len and path[i + 1] == '.') {
            const at_end = i + 2 >= path.len;
            const next_is_slash = !at_end and path[i + 2] == '/';
            if (at_end or next_is_slash) {
                i += if (next_is_slash) 2 else 1;
                continue;
            }
        }

        try writer.writeByte(path[i]);
        wrote_any = true;
        i += 1;
    }

    if (!wrote_any) {
        try writer.writeByte('.');
    }
}

const FileCache = struct {
    allocator: std.mem.Allocator,
    map: std.StringHashMap([]const u8),

    fn init(allocator: std.mem.Allocator) FileCache {
        return .{
            .allocator = allocator,
            .map = std.StringHashMap([]const u8).init(allocator),
        };
    }

    fn deinit(self: *FileCache) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.deinit();
    }

    fn get(self: *FileCache, io: std.Io, path: []const u8) !?[]const u8 {
        if (self.map.get(path)) |cached| return cached;

        const cwd = std.Io.Dir.cwd();
        const content = cwd.readFileAlloc(io, path, self.allocator, .unlimited) catch return null;
        const key = try self.allocator.dupe(u8, path);
        try self.map.put(key, content);
        return content;
    }
};
