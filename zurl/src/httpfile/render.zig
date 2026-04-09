const std = @import("std");
const model = @import("model.zig");
const template = @import("template.zig");

pub fn renderRequest(
    allocator: std.mem.Allocator,
    document: *const model.Document,
    request: *const model.Request,
    external_vars: *const std.StringHashMap([]const u8),
    env_map: *const std.process.Environ.Map,
) !model.ResolvedRequest {
    var document_vars = std.StringHashMap(model.TemplateString).init(allocator);
    defer document_vars.deinit();
    for (document.variables) |variable| {
        try document_vars.put(variable.name, variable.value);
    }

    var visiting = std.StringHashMap(void).init(allocator);
    defer visiting.deinit();
    const options: template.ResolveOptions = .{
        .allocator = allocator,
        .external_vars = external_vars,
        .document_vars = &document_vars,
        .env_map = env_map,
    };

    var headers = std.ArrayList(model.ResolvedHeader).empty;
    defer headers.deinit(allocator);
    for (request.headers) |header| {
        try headers.append(allocator, .{
            .name = try allocator.dupe(u8, header.name),
            .value = try template.renderTemplate(options, header.value, &visiting),
        });
    }

    const body = if (request.body) |value| try renderBody(allocator, document, options, value, &visiting) else null;
    errdefer if (body) |text| allocator.free(text);

    return .{
        .name = if (request.name) |value| try allocator.dupe(u8, value) else null,
        .description = if (request.description) |value| try allocator.dupe(u8, value) else null,
        .tags = try dupeTags(allocator, request.tags),
        .method = request.method,
        .target = try template.renderTemplate(options, request.target, &visiting),
        .headers = try headers.toOwnedSlice(allocator),
        .body = body,
    };
}

pub fn renderDocument(
    allocator: std.mem.Allocator,
    document: *const model.Document,
    external_vars: *const std.StringHashMap([]const u8),
    env_map: *const std.process.Environ.Map,
) ![]model.ResolvedRequest {
    var requests = std.ArrayList(model.ResolvedRequest).empty;
    defer requests.deinit(allocator);
    for (document.requests) |*request| {
        try requests.append(allocator, try renderRequest(allocator, document, request, external_vars, env_map));
    }
    return requests.toOwnedSlice(allocator);
}

fn renderBody(
    allocator: std.mem.Allocator,
    document: *const model.Document,
    options: template.ResolveOptions,
    body: model.Body,
    visiting: *std.StringHashMap(void),
) ![]u8 {
    switch (body) {
        .@"inline" => |value| return template.renderTemplate(options, value, visiting),
        .file_include => |relative_path| {
            const source_path = document.source_path orelse return error.MissingSourcePath;
            const base_dir = std.fs.path.dirname(source_path) orelse ".";
            const full_path = try std.fs.path.join(allocator, &.{ base_dir, relative_path });
            defer allocator.free(full_path);
            const io = std.Io.Threaded.global_single_threaded.io();
            const file_text = std.Io.Dir.cwd().readFileAlloc(io, full_path, allocator, .limited(std.math.maxInt(usize))) catch {
                return error.FileIncludeNotFound;
            };
            defer allocator.free(file_text);

            const parsed = try template.parseTemplate(allocator, file_text);
            defer parsed.deinit(allocator);
            return template.renderTemplate(options, parsed, visiting);
        },
    }
}

fn dupeTags(allocator: std.mem.Allocator, tags: []const []const u8) ![]const []const u8 {
    const out = try allocator.alloc([]const u8, tags.len);
    errdefer allocator.free(out);
    for (tags, 0..) |tag, idx| out[idx] = try allocator.dupe(u8, tag);
    return out;
}

test "render resolves variables" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const source =
        \\@host = example.com
        \\GET https://{{host}}/{{path}}
    ;
    var document = try @import("parser.zig").parse(allocator, source);
    defer document.deinit(allocator);

    var external = std.StringHashMap([]const u8).init(allocator);
    defer external.deinit();
    try external.put("path", "users");
    var env = std.process.Environ.Map.init(allocator);
    defer env.deinit();

    var rendered = try renderRequest(allocator, &document, &document.requests[0], &external, &env);
    defer rendered.deinit(allocator);
    try testing.expectEqualStrings("https://example.com/users", rendered.target);
}
