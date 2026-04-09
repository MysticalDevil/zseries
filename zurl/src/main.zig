const std = @import("std");
const zcli = @import("zcli");
const zurl = @import("zurl");

const httpfile = zurl.httpfile;

const root_help = zcli.help.Command{
    .name = "zurl",
    .summary = ".http parser and renderer",
    .subcommands = &.{
        .{ .name = "parse", .summary = "Parse a .http document" },
        .{ .name = "render", .summary = "Render a .http document" },
        .{ .name = "run", .summary = "Execute a .http document" },
    },
};

const parse_help = zcli.help.Command{
    .name = "parse",
    .summary = "Parse a .http document",
    .args = &.{.{ .name = "file", .description = ".http file path" }},
    .flags = &.{.{ .name = "--format", .value_name = "text|json", .description = "Output format" }},
};

const render_help = zcli.help.Command{
    .name = "render",
    .summary = "Render a .http document",
    .args = &.{.{ .name = "file", .description = ".http file path" }},
    .flags = &.{
        .{ .name = "--request", .value_name = "NAME", .description = "Render only one named request" },
        .{ .name = "--var", .value_name = "KEY=VALUE", .description = "Repeatable external variables" },
        .{ .name = "--format", .value_name = "http|text|json", .description = "Output format" },
    },
};

const run_help = zcli.help.Command{
    .name = "run",
    .summary = "Execute a .http document",
    .args = &.{.{ .name = "file", .description = ".http file path" }},
    .flags = &.{
        .{ .name = "--request", .value_name = "NAME", .description = "Run only one named request" },
        .{ .name = "--var", .value_name = "KEY=VALUE", .description = "Repeatable external variables" },
    },
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = init.minimal.args.toSlice(allocator) catch |err| {
        std.debug.print("error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    run(allocator, init.io, init.environ_map, args) catch |err| {
        std.debug.print("error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn run(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    if (args.len < 2 or std.mem.eql(u8, args[1], "help") or std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
        try printHelp(io, env, root_help);
        return;
    }

    if (std.mem.eql(u8, args[1], "parse")) {
        if (zcli.args.hasFlag(args[2..], "--help") or zcli.args.hasFlag(args[2..], "-h")) {
            try printHelp(io, env, parse_help);
            return;
        }
        return runParse(allocator, io, args[2..]);
    }

    if (std.mem.eql(u8, args[1], "render")) {
        if (zcli.args.hasFlag(args[2..], "--help") or zcli.args.hasFlag(args[2..], "-h")) {
            try printHelp(io, env, render_help);
            return;
        }
        return runRender(allocator, io, env, args[2..]);
    }

    if (std.mem.eql(u8, args[1], "run")) {
        if (zcli.args.hasFlag(args[2..], "--help") or zcli.args.hasFlag(args[2..], "-h")) {
            try printHelp(io, env, run_help);
            return;
        }
        return runExecute(allocator, io, env, args[2..]);
    }

    return error.InvalidCliArgs;
}

fn printHelp(io: std.Io, env: *const std.process.Environ.Map, command: zcli.help.Command) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const writer = &stderr_writer.interface;
    try zcli.help.writeHelp(writer, command, .{
        .use_color = zcli.color.enabled(env),
        .prog_name = "zurl",
    });
    try writer.flush();
}

fn runParse(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    const file_path = firstPositional(args) orelse return error.InvalidCliArgs;
    var document = try httpfile.parseFile(allocator, file_path);
    defer document.deinit(allocator);

    const format = zcli.args.flagValue(args, "--format") orelse "text";
    if (std.mem.eql(u8, format, "json")) {
        return printDocumentJson(allocator, io, &document);
    }
    return printDocumentText(io, &document);
}

fn runRender(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    var inputs = try loadInputs(allocator, args);
    defer inputs.deinit();

    const format = zcli.args.flagValue(args, "--format") orelse "http";
    if (zcli.args.flagValue(args, "--request")) |name| {
        const request = httpfile.findRequestByName(&inputs.document, name) orelse return error.RequestNotFound;
        var rendered = try httpfile.renderRequest(allocator, &inputs.document, request, &inputs.external, env);
        defer rendered.deinit(allocator);
        return printRendered(allocator, io, &.{rendered}, format);
    }

    const rendered = try httpfile.renderDocument(allocator, &inputs.document, &inputs.external, env);
    defer {
        for (rendered) |item| item.deinit(allocator);
        allocator.free(rendered);
    }
    return printRendered(allocator, io, rendered, format);
}

fn runExecute(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    var inputs = try loadInputs(allocator, args);
    defer inputs.deinit();

    var session = httpfile.runner.Session.init(allocator, io);
    defer session.deinit();

    if (zcli.args.flagValue(args, "--request")) |name| {
        const request = httpfile.findRequestByName(&inputs.document, name) orelse return error.RequestNotFound;
        var rendered = try httpfile.renderRequest(allocator, &inputs.document, request, &inputs.external, env);
        defer rendered.deinit(allocator);
        var response = try session.execute(&rendered);
        defer response.deinit(allocator);
        return printExecution(io, &rendered, &response);
    }

    const rendered = try httpfile.renderDocument(allocator, &inputs.document, &inputs.external, env);
    defer {
        for (rendered) |item| item.deinit(allocator);
        allocator.free(rendered);
    }

    for (rendered, 0..) |*request, idx| {
        var response = try session.execute(request);
        defer response.deinit(allocator);
        if (idx > 0) {
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
            const writer = &stdout_writer.interface;
            try writer.writeAll("\n");
            try writer.flush();
        }
        try printExecution(io, request, &response);
    }
}

const LoadedInputs = struct {
    allocator: std.mem.Allocator,
    document: httpfile.Document,
    external: std.StringHashMap([]const u8),

    fn deinit(self: *LoadedInputs) void {
        self.document.deinit(self.allocator);
        var iter = self.external.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.external.deinit();
    }
};

fn loadInputs(allocator: std.mem.Allocator, args: []const []const u8) !LoadedInputs {
    const file_path = firstPositional(args) orelse return error.InvalidCliArgs;
    var external = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var iter = external.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        external.deinit();
    }

    try loadExternalVars(allocator, &external, args);
    return .{
        .allocator = allocator,
        .document = try httpfile.parseFile(allocator, file_path),
        .external = external,
    };
}

fn loadExternalVars(allocator: std.mem.Allocator, vars: *std.StringHashMap([]const u8), args: []const []const u8) !void {
    const entries = try zcli.args.repeatedFlags(allocator, args, "--var");
    defer {
        for (entries) |entry| allocator.free(entry);
        allocator.free(entries);
    }

    for (entries) |entry| {
        const equals = std.mem.indexOfScalar(u8, entry, '=') orelse return error.InvalidCliArgs;
        const key = std.mem.trim(u8, entry[0..equals], " \t");
        const value = entry[equals + 1 ..];
        if (key.len == 0) return error.InvalidCliArgs;
        try vars.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));
    }
}

fn firstPositional(args: []const []const u8) ?[]const u8 {
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.eql(u8, arg, "--format") or std.mem.eql(u8, arg, "--request") or std.mem.eql(u8, arg, "--var")) {
                index += 1;
            }
            continue;
        }
        return arg;
    }
    return null;
}

fn printDocumentText(io: std.Io, document: *const httpfile.Document) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_writer.interface;
    try writer.print("variables: {d}\nrequests: {d}\n", .{ document.variables.len, document.requests.len });
    for (document.requests) |request| {
        try writer.print("- {s} {s} headers={d}\n", .{ @tagName(request.method), request.name orelse "<unnamed>", request.headers.len });
    }
    try writer.flush();
}

fn printDocumentJson(allocator: std.mem.Allocator, io: std.Io, document: *const httpfile.Document) !void {
    var names = std.ArrayList([]const u8).empty;
    defer names.deinit(allocator);
    for (document.requests) |request| {
        try names.append(allocator, request.name orelse "");
    }
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_writer.interface;
    try zcli.format.writeJson(writer, .{
        .variables = document.variables.len,
        .requests = document.requests.len,
        .names = names.items,
    }, .{ .stringify = .{ .whitespace = .indent_2 } });
    try writer.writeByte('\n');
    try writer.flush();
}

fn printRendered(allocator: std.mem.Allocator, io: std.Io, requests: []const httpfile.ResolvedRequest, format: []const u8) !void {
    if (std.mem.eql(u8, format, "json")) {
        return printRenderedJson(allocator, io, requests);
    }
    if (std.mem.eql(u8, format, "text")) {
        return printRenderedText(io, requests);
    }
    return printRenderedHttp(io, requests);
}

fn printRenderedText(io: std.Io, requests: []const httpfile.ResolvedRequest) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_writer.interface;
    for (requests) |request| {
        try writer.print("- {s} {s}\n", .{ @tagName(request.method), request.target });
    }
    try writer.flush();
}

fn printRenderedHttp(io: std.Io, requests: []const httpfile.ResolvedRequest) !void {
    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_writer.interface;
    for (requests, 0..) |request, idx| {
        if (idx > 0) try writer.writeAll("\n###\n");
        try writer.print("{s} {s}\n", .{ @tagName(request.method), request.target });
        for (request.headers) |header| {
            try writer.print("{s}: {s}\n", .{ header.name, header.value });
        }
        if (request.body) |body| {
            try writer.writeByte('\n');
            try writer.writeAll(body);
            try writer.writeByte('\n');
        }
    }
    try writer.flush();
}

fn printRenderedJson(allocator: std.mem.Allocator, io: std.Io, requests: []const httpfile.ResolvedRequest) !void {
    var items = std.ArrayList(struct { name: []const u8, method: []const u8, target: []const u8 }).empty;
    defer items.deinit(allocator);
    for (requests) |request| {
        try items.append(allocator, .{
            .name = request.name orelse "",
            .method = @tagName(request.method),
            .target = request.target,
        });
    }
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_writer.interface;
    try zcli.format.writeJson(writer, .{ .requests = items.items }, .{ .stringify = .{ .whitespace = .indent_2 } });
    try writer.writeByte('\n');
    try writer.flush();
}

fn printExecution(io: std.Io, request: *const httpfile.ResolvedRequest, response: *const httpfile.runner.Response) !void {
    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_writer.interface;

    try writer.print("> {s} {s}\n", .{ @tagName(request.method), request.target });
    try writer.print("< {d} {s}\n", .{ @intFromEnum(response.status), @tagName(response.status) });
    for (response.headers) |header| {
        try writer.print("< {s}: {s}\n", .{ header.name, header.value });
    }
    if (response.body.len > 0) {
        try writer.writeByte('\n');
        try writer.writeAll(response.body);
        try writer.writeByte('\n');
    }
    try writer.flush();
}
