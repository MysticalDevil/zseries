const std = @import("std");
const errors = @import("error.zig");
const model = @import("model.zig");

pub const ResolveOptions = struct {
    allocator: std.mem.Allocator,
    external_vars: *const std.StringHashMap([]const u8),
    document_vars: *const std.StringHashMap(model.TemplateString),
    env_map: *const std.process.Environ.Map,
};

pub fn parseTemplate(allocator: std.mem.Allocator, input: []const u8) errors.Error!model.TemplateString {
    var segments = std.ArrayList(model.Segment).empty;
    defer segments.deinit(allocator);

    var cursor: usize = 0;
    while (cursor < input.len) {
        const open = std.mem.indexOfPos(u8, input, cursor, "{{");
        const start = if (open) |value| value else {
            try appendText(allocator, &segments, input[cursor..]);
            break;
        };
        if (start > cursor) {
            try appendText(allocator, &segments, input[cursor..start]);
        }

        const close = std.mem.indexOfPos(u8, input, start + 2, "}}");
        const end = close orelse return error.UnclosedInterpolation;
        const raw = std.mem.trim(u8, input[start + 2 .. end], " \t");
        if (raw.len == 0) return error.EmptyInterpolationName;

        if (std.mem.startsWith(u8, raw, "$env")) {
            if (raw.len == 4) return error.InvalidEnvInterpolation;
            if (!std.ascii.isWhitespace(raw[4])) return error.InvalidEnvInterpolation;

            const name = std.mem.trim(u8, raw[5..], " \t");
            if (name.len == 0) return error.InvalidEnvInterpolation;
            try segments.append(allocator, .{ .env = try allocator.dupe(u8, name) });
        } else {
            try segments.append(allocator, .{ .variable = try allocator.dupe(u8, raw) });
        }

        cursor = end + 2;
    }

    return .{ .segments = try segments.toOwnedSlice(allocator) };
}

fn appendText(allocator: std.mem.Allocator, segments: *std.ArrayList(model.Segment), text: []const u8) !void {
    if (text.len == 0) return;
    try segments.append(allocator, .{ .text = try allocator.dupe(u8, text) });
}

pub fn renderTemplate(options: ResolveOptions, value: model.TemplateString, visiting: *std.StringHashMap(void)) errors.Error![]u8 {
    var writer: std.Io.Writer.Allocating = .init(options.allocator);
    defer writer.deinit();

    for (value.segments) |segment| {
        switch (segment) {
            .text => |text| try writer.writer.writeAll(text),
            .env => |name| {
                const env_value = options.env_map.get(name) orelse return error.UndefinedVariable;
                try writer.writer.writeAll(env_value);
            },
            .variable => |name| {
                const resolved = try resolveVariable(options, name, visiting);
                defer options.allocator.free(resolved);
                try writer.writer.writeAll(resolved);
            },
        }
    }

    return writer.toOwnedSlice();
}

fn resolveVariable(options: ResolveOptions, name: []const u8, visiting: *std.StringHashMap(void)) errors.Error![]u8 {
    if (options.external_vars.get(name)) |value| {
        return try options.allocator.dupe(u8, value);
    }
    if (visiting.contains(name)) return error.CircularVariableReference;
    if (options.document_vars.get(name)) |value| {
        try visiting.put(name, {});
        defer std.debug.assert(visiting.remove(name));
        return renderTemplate(options, value, visiting);
    }
    return error.UndefinedVariable;
}

test "parse template supports variable and env segments" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const parsed = try parseTemplate(allocator, "https://{{host}}/{{$env TOKEN}}");
    defer parsed.deinit(allocator);
    try testing.expectEqual(@as(usize, 4), parsed.segments.len);
}

test "parse template rejects malformed env interpolation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    try testing.expectError(error.InvalidEnvInterpolation, parseTemplate(allocator, "{{$envTOKEN}}"));
    try testing.expectError(error.InvalidEnvInterpolation, parseTemplate(allocator, "{{$env}}"));
}
