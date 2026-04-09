const std = @import("std");
const model = @import("model.zig");
const template = @import("template.zig");

const PendingMeta = struct {
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    tags: std.ArrayList([]const u8) = .empty,

    fn deinit(self: *PendingMeta, allocator: std.mem.Allocator) void {
        if (self.name) |value| allocator.free(value);
        if (self.description) |value| allocator.free(value);
        for (self.tags.items) |tag| allocator.free(tag);
        self.tags.deinit(allocator);
    }
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !model.Document {
    return parseInternal(allocator, source, null);
}

pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !model.Document {
    const io = std.Io.Threaded.global_single_threaded.io();
    const source = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(std.math.maxInt(usize)));
    defer allocator.free(source);

    const source_path = try allocator.dupe(u8, path);
    errdefer allocator.free(source_path);

    return parseInternal(allocator, source, source_path);
}

fn parseInternal(allocator: std.mem.Allocator, source: []const u8, source_path: ?[]const u8) !model.Document {
    var variables = std.ArrayList(model.VariableDecl).empty;
    errdefer {
        for (variables.items) |item| item.deinit(allocator);
        variables.deinit(allocator);
    }

    var requests = std.ArrayList(model.Request).empty;
    errdefer {
        for (requests.items) |item| item.deinit(allocator);
        requests.deinit(allocator);
    }

    var pending = PendingMeta{};
    defer pending.deinit(allocator);

    var section = std.ArrayList([]const u8).empty;
    defer section.deinit(allocator);

    var iter = std.mem.splitScalar(u8, source, '\n');
    var line_number: usize = 0;
    while (iter.next()) |raw_line| {
        line_number += 1;
        const line = if (raw_line.len > 0 and raw_line[raw_line.len - 1] == '\r') raw_line[0 .. raw_line.len - 1] else raw_line;
        const trimmed = std.mem.trim(u8, line, " \t");
        if (isRequestSeparator(trimmed)) {
            try finalizeSection(allocator, &variables, &requests, &pending, section.items, line_number - section.items.len);
            for (section.items) |value| allocator.free(value);
            section.clearRetainingCapacity();
            continue;
        }
        try section.append(allocator, try allocator.dupe(u8, line));
    }

    try finalizeSection(allocator, &variables, &requests, &pending, section.items, line_number + 1 - section.items.len);
    for (section.items) |value| allocator.free(value);

    return .{
        .variables = try variables.toOwnedSlice(allocator),
        .requests = try requests.toOwnedSlice(allocator),
        .source_path = source_path,
    };
}

fn isRequestSeparator(trimmed: []const u8) bool {
    if (!std.mem.startsWith(u8, trimmed, "###")) return false;
    if (trimmed.len == 3) return true;
    return std.ascii.isWhitespace(trimmed[3]);
}

fn finalizeSection(
    allocator: std.mem.Allocator,
    variables: *std.ArrayList(model.VariableDecl),
    requests: *std.ArrayList(model.Request),
    pending: *PendingMeta,
    lines: []const []const u8,
    first_line_number: usize,
) !void {
    var has_content = false;
    for (lines) |line| {
        if (std.mem.trim(u8, line, " \t").len != 0) {
            has_content = true;
            break;
        }
    }
    if (!has_content) return;

    var request_method: ?std.http.Method = null;
    var request_target: ?model.TemplateString = null;
    var request_location = model.SourceLocation{ .line = first_line_number, .column = 1 };
    var headers = std.ArrayList(model.Header).empty;
    defer headers.deinit(allocator);
    var body_lines = std.ArrayList([]const u8).empty;
    defer {
        for (body_lines.items) |line| allocator.free(line);
        body_lines.deinit(allocator);
    }
    var in_body = false;

    for (lines, 0..) |line, idx| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (!in_body and request_method == null and trimmed.len == 0) continue;

        if (!in_body and request_method == null and std.mem.startsWith(u8, trimmed, "#")) {
            try parseMetadataLine(allocator, pending, trimmed);
            continue;
        }

        if (!in_body and request_method == null and trimmed.len != 0 and trimmed[0] == '@') {
            try parseVariableLine(allocator, variables, trimmed, first_line_number + idx);
            continue;
        }

        if (request_method == null) {
            const request = try parseRequestLine(allocator, trimmed);
            request_method = request.method;
            request_target = request.target;
            request_location = .{ .line = first_line_number + idx, .column = 1 };
            continue;
        }

        if (!in_body) {
            if (trimmed.len == 0) {
                in_body = true;
                continue;
            }
            try headers.append(allocator, try parseHeaderLine(allocator, line, first_line_number + idx));
            continue;
        }

        try body_lines.append(allocator, try allocator.dupe(u8, line));
    }

    if (request_method == null) {
        return;
    }

    const method = request_method orelse return error.MissingRequest;
    const target = request_target orelse return error.MissingRequest;
    errdefer target.deinit(allocator);

    const tags = try pending.tags.toOwnedSlice(allocator);
    pending.tags = .empty;
    const name = pending.name;
    pending.name = null;
    const description = pending.description;
    pending.description = null;

    const body = try parseBody(allocator, body_lines.items);
    errdefer if (body) |value| value.deinit(allocator);

    try requests.append(allocator, .{
        .name = name,
        .description = description,
        .tags = tags,
        .method = method,
        .target = target,
        .headers = try headers.toOwnedSlice(allocator),
        .body = body,
        .location = request_location,
    });
}

fn parseMetadataLine(allocator: std.mem.Allocator, pending: *PendingMeta, trimmed: []const u8) !void {
    if (!std.mem.startsWith(u8, trimmed, "# @")) return;
    const payload = trimmed[3..];
    const split_at = std.mem.indexOfScalar(u8, payload, ' ') orelse return error.InvalidMetadata;
    const key = payload[0..split_at];
    const value = std.mem.trim(u8, payload[split_at + 1 ..], " \t");
    if (value.len == 0) return error.InvalidMetadata;

    if (std.mem.eql(u8, key, "name")) {
        if (pending.name) |existing| allocator.free(existing);
        pending.name = try allocator.dupe(u8, value);
        return;
    }
    if (std.mem.eql(u8, key, "description")) {
        if (pending.description) |existing| allocator.free(existing);
        pending.description = try allocator.dupe(u8, value);
        return;
    }
    if (std.mem.eql(u8, key, "tag")) {
        try pending.tags.append(allocator, try allocator.dupe(u8, value));
        return;
    }
    return error.InvalidMetadata;
}

fn parseVariableLine(allocator: std.mem.Allocator, variables: *std.ArrayList(model.VariableDecl), trimmed: []const u8, line: usize) !void {
    const equals = std.mem.indexOfScalar(u8, trimmed, '=') orelse return error.InvalidVariableDeclaration;
    const name = std.mem.trim(u8, trimmed[1..equals], " \t");
    const value = std.mem.trim(u8, trimmed[equals + 1 ..], " \t");
    if (name.len == 0) return error.InvalidVariableDeclaration;
    for (variables.items) |item| {
        if (std.mem.eql(u8, item.name, name)) return error.DuplicateVariable;
    }
    try variables.append(allocator, .{
        .name = try allocator.dupe(u8, name),
        .value = try template.parseTemplate(allocator, value),
        .location = .{ .line = line, .column = 1 },
    });
}

fn parseRequestLine(allocator: std.mem.Allocator, trimmed: []const u8) !struct { method: std.http.Method, target: model.TemplateString } {
    var parts = std.mem.splitScalar(u8, trimmed, ' ');
    const method_text = parts.next() orelse return error.InvalidRequestLine;
    const target = std.mem.trim(u8, parts.rest(), " \t");
    if (target.len == 0) return error.InvalidRequestLine;
    return .{
        .method = parseMethod(method_text) orelse return error.InvalidMethod,
        .target = try template.parseTemplate(allocator, target),
    };
}

fn parseMethod(value: []const u8) ?std.http.Method {
    if (std.mem.eql(u8, value, "GET")) return .GET;
    if (std.mem.eql(u8, value, "HEAD")) return .HEAD;
    if (std.mem.eql(u8, value, "POST")) return .POST;
    if (std.mem.eql(u8, value, "PUT")) return .PUT;
    if (std.mem.eql(u8, value, "DELETE")) return .DELETE;
    if (std.mem.eql(u8, value, "CONNECT")) return .CONNECT;
    if (std.mem.eql(u8, value, "OPTIONS")) return .OPTIONS;
    if (std.mem.eql(u8, value, "TRACE")) return .TRACE;
    if (std.mem.eql(u8, value, "PATCH")) return .PATCH;
    return null;
}

fn parseHeaderLine(allocator: std.mem.Allocator, line: []const u8, line_number: usize) !model.Header {
    const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.MissingHeaderSeparator;
    const name = std.mem.trim(u8, line[0..colon], " \t");
    const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
    if (name.len == 0) return error.InvalidHeader;
    return .{
        .name = try allocator.dupe(u8, name),
        .value = try template.parseTemplate(allocator, value),
        .location = .{ .line = line_number, .column = 1 },
    };
}

fn parseBody(allocator: std.mem.Allocator, body_lines: []const []const u8) !?model.Body {
    var effective_len = body_lines.len;
    while (effective_len > 0) {
        const trailing = std.mem.trim(u8, body_lines[effective_len - 1], " \t");
        if (trailing.len != 0) break;
        effective_len -= 1;
    }

    if (effective_len == 0) return null;
    const effective_lines = body_lines[0..effective_len];

    if (effective_lines.len == 1) {
        const trimmed = std.mem.trim(u8, effective_lines[0], " \t");
        if (std.mem.startsWith(u8, trimmed, "< ")) {
            const path = std.mem.trim(u8, trimmed[1..], " \t");
            if (path.len == 0) return error.UnexpectedContent;
            return .{ .file_include = try allocator.dupe(u8, path) };
        }
    }
    var writer: std.Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();
    for (effective_lines, 0..) |line, idx| {
        if (idx > 0) try writer.writer.writeByte('\n');
        try writer.writer.writeAll(line);
    }
    const body_text = try writer.toOwnedSlice();
    defer allocator.free(body_text);
    return .{ .@"inline" = try template.parseTemplate(allocator, body_text) };
}

test "parse supports variables and metadata" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const source =
        \\@host = example.com
        \\# @name smoke
        \\# @description demo request
        \\# @tag demo
        \\GET https://{{host}}/users
        \\Accept: application/json
        \\
        \\{"ok":true}
    ;
    var document = try parse(allocator, source);
    defer document.deinit(allocator);
    try testing.expectEqual(@as(usize, 1), document.variables.len);
    try testing.expectEqual(@as(usize, 1), document.requests.len);
}
