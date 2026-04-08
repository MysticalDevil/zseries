const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");
const names = @import("../ast/names.zig");
const rule_ids = @import("../rule_ids.zig");

const writer_methods = [_][]const u8{ "write", "writeAll", "writeByte", "writeBytesNTimes", "print" };
const reader_methods = [_][]const u8{ "read", "readAll", "readByte", "readUntilDelimiter", "readUntilDelimiterOrEof" };

pub fn run(ctx: *RuleContext) !void {
    if (ctx.shouldSkipFile()) return;

    var severity = Severity.err;
    var aliases: []const []const u8 = &.{ "writer", "reader", "out_writer", "in_reader", "w", "r" };
    var allow_types: []const []const u8 = &.{};

    if (ctx.config.rules.no_anytype_io_params) |cfg| {
        severity = Severity.fromString(cfg.base.severity) orelse Severity.err;
        aliases = cfg.io_param_aliases;
        allow_types = cfg.allow_types;
    }

    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);

        if (tag == .fn_decl) {
            if (ctx.shouldSkipNode(node)) continue;
            ctx.traceNodeBestEffort(2, node, "inspect");
            try checkFnDecl(ctx, node, severity, aliases, allow_types);
            continue;
        }

        const is_container_field = tag == .container_field or
            tag == .container_field_align or
            tag == .container_field_init;

        if (is_container_field) {
            if (ctx.shouldSkipNode(node)) continue;
            ctx.traceNodeBestEffort(2, node, "inspect");
            try checkContainerField(ctx, node, severity, aliases, allow_types);
        }
    }
}

fn checkFnDecl(
    ctx: *RuleContext,
    fn_node: std.zig.Ast.Node.Index,
    severity: Severity,
    aliases: []const []const u8,
    allow_types: []const []const u8,
) !void {
    const ast = ctx.file.ast;
    var proto_buf: [1]std.zig.Ast.Node.Index = undefined;
    const proto = ast.fullFnProto(&proto_buf, fn_node) orelse return;
    const body_node = ast.nodeData(fn_node).node_and_node[1];

    var iter = proto.iterate(&ast);
    while (iter.next()) |param| {
        if (param.anytype_ellipsis3 == null) continue;
        const name_tok = param.name_token orelse continue;
        const param_name = ast.tokenSlice(name_tok);

        const is_alias = inList(param_name, aliases);
        const inferred_io = !is_alias and inferIoUsageInFunction(ast, body_node, param_name);
        if (!is_alias and !inferred_io) continue;

        if (param.type_expr) |type_expr| {
            if (isAllowedIoType(ast, type_expr, allow_types, ctx.allocator)) continue;
        }

        const loc = locations.getTokenLocation(ast, name_tok, ctx.file.content);
        ctx.traceNodeBestEffort(2, fn_node, "match");
        var msg_buf: [240]u8 = undefined;
        const msg = try std.fmt.bufPrint(
            &msg_buf,
            "io-like parameter '{s}' must not use anytype; use std.Io.Writer/std.Io.Reader or pointer interface types",
            .{param_name},
        );
        try ctx.addDiagnostic(rule_ids.no_anytype_io_params, severity, loc.line, loc.column, msg);
    }
}

fn checkContainerField(
    ctx: *RuleContext,
    field_node: std.zig.Ast.Node.Index,
    severity: Severity,
    aliases: []const []const u8,
    allow_types: []const []const u8,
) !void {
    const ast = ctx.file.ast;
    const full_field = ast.fullContainerField(field_node) orelse return;
    const field_name = ast.tokenSlice(full_field.ast.main_token);
    if (!inList(field_name, aliases)) return;

    const type_expr = full_field.ast.type_expr.unwrap() orelse return;
    if (!isAnytypeType(ast, type_expr)) return;

    if (isAllowedIoType(ast, type_expr, allow_types, ctx.allocator)) return;

    const loc = locations.getTokenLocation(ast, full_field.ast.main_token, ctx.file.content);
    ctx.traceNodeBestEffort(2, field_node, "match");
    var msg_buf: [240]u8 = undefined;
    const msg = try std.fmt.bufPrint(
        &msg_buf,
        "io-like field '{s}' must not use anytype; use std.Io.Writer/std.Io.Reader or pointer interface types",
        .{field_name},
    );
    try ctx.addDiagnostic(rule_ids.no_anytype_io_params, severity, loc.line, loc.column, msg);
}

fn inferIoUsageInFunction(ast: std.zig.Ast, body_node: std.zig.Ast.Node.Index, param_name: []const u8) bool {
    if (@intFromEnum(body_node) == 0) return false;

    const tags = ast.nodes.items(.tag);
    for (tags, 0..) |tag, i| {
        switch (tag) {
            .call, .call_comma, .call_one, .call_one_comma => {},
            else => continue,
        }

        const call_node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (!isInsideNode(ast, body_node, call_node)) continue;

        const fn_expr = getCallFunctionExpr(ast, call_node) orelse continue;
        if (ast.nodeTag(fn_expr) != .field_access) continue;

        const data = ast.nodeData(fn_expr);
        const lhs = data.node_and_token[0];
        if (ast.nodeTag(lhs) != .identifier) continue;

        const base_tok = ast.nodes.items(.main_token)[@intFromEnum(lhs)];
        if (!std.mem.eql(u8, ast.tokenSlice(base_tok), param_name)) continue;

        const method_name = ast.tokenSlice(data.node_and_token[1]);
        if (inList(method_name, &writer_methods) or inList(method_name, &reader_methods)) return true;
    }

    return false;
}

fn getCallFunctionExpr(ast: std.zig.Ast, call_node: std.zig.Ast.Node.Index) ?std.zig.Ast.Node.Index {
    var buffer: [1]std.zig.Ast.Node.Index = undefined;
    const full_call = ast.fullCall(&buffer, call_node) orelse return null;
    return full_call.ast.fn_expr;
}

fn isAllowedIoType(
    ast: std.zig.Ast,
    type_node: std.zig.Ast.Node.Index,
    allow_types: []const []const u8,
    allocator: std.mem.Allocator,
) bool {
    if (isNamedIoType(ast, type_node, allow_types, allocator)) return true;

    if (ast.fullPtrType(type_node)) |ptr| {
        return isNamedIoType(ast, ptr.ast.child_type, allow_types, allocator);
    }

    return false;
}

fn isNamedIoType(
    ast: std.zig.Ast,
    type_node: std.zig.Ast.Node.Index,
    allow_types: []const []const u8,
    allocator: std.mem.Allocator,
) bool {
    var path_buf = std.ArrayList(u8).empty;
    defer path_buf.deinit(allocator);

    const path = names.extractPath(ast, type_node, &path_buf, allocator) catch return false;
    defer if (path) |p| allocator.free(p);

    const p = path orelse return false;
    if (std.mem.eql(u8, p, "std.Io.Writer") or std.mem.eql(u8, p, "std.Io.Reader")) return true;
    return inList(p, allow_types);
}

fn isAnytypeType(ast: std.zig.Ast, type_node: std.zig.Ast.Node.Index) bool {
    if (ast.nodeTag(type_node) != .identifier) return false;
    const tok = ast.nodes.items(.main_token)[@intFromEnum(type_node)];
    return std.mem.eql(u8, ast.tokenSlice(tok), "anytype");
}

fn isInsideNode(ast: std.zig.Ast, parent: std.zig.Ast.Node.Index, node: std.zig.Ast.Node.Index) bool {
    const p_first = ast.firstToken(parent);
    const p_last = ast.lastToken(parent);
    const n_first = ast.firstToken(node);
    const n_last = ast.lastToken(node);
    return n_first >= p_first and n_last <= p_last;
}

fn inList(name: []const u8, list: []const []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, name, item)) return true;
    }
    return false;
}

test "no_anytype_io_params corpus" {
    const allocator = std.testing.allocator;

    const Case = struct {
        name: []const u8,
        source: []const u8,
        path: []const u8,
        expected: usize,
    };

    const cases = [_]Case{
        .{
            .name = "writer anytype parameter",
            .source =
            \\const std = @import("std");
            \\pub fn emit(writer: anytype, msg: []const u8) !void {
            \\    try writer.writeAll(msg);
            \\}
            ,
            .path = "src/sample.zig",
            .expected = 1,
        },
        .{
            .name = "concrete std io writer",
            .source =
            \\const std = @import("std");
            \\pub fn emit(writer: *std.Io.Writer, msg: []const u8) !void {
            \\    try writer.writeAll(msg);
            \\}
            ,
            .path = "src/sample.zig",
            .expected = 0,
        },
        .{
            .name = "writer anytype field",
            .source =
            \\const std = @import("std");
            \\const Sink = struct {
            \\    writer: anytype,
            \\};
            ,
            .path = "src/sample.zig",
            .expected = 1,
        },
        .{
            .name = "skip test file",
            .source =
            \\const std = @import("std");
            \\pub fn emit(writer: anytype, msg: []const u8) !void {
            \\    try writer.writeAll(msg);
            \\}
            ,
            .path = "src/example_test.zig",
            .expected = 0,
        },
    };

    for (cases) |c| {
        const count = try runRuleOnSource(allocator, c.source, c.path);
        try std.testing.expectEqual(c.expected, count);
    }
}

fn runRuleOnSource(
    allocator: std.mem.Allocator,
    source: []const u8,
    path: []const u8,
) !usize {
    const content = try allocator.dupeZ(u8, source);
    defer allocator.free(content);

    var ast = try std.zig.Ast.parse(allocator, content, .zig);
    defer ast.deinit(allocator);

    const SourceFile = @import("../source_file.zig").SourceFile;
    const IgnoreDirectives = @import("../ignore_directives.zig").IgnoreDirectives;
    const DiagnosticCollection = @import("../diagnostic.zig").DiagnosticCollection;
    const Config = @import("../config.zig").Config;

    var file = SourceFile{
        .allocator = allocator,
        .path = path,
        .content = content,
        .ast = ast,
    };

    var ignores = IgnoreDirectives.init(allocator);
    defer ignores.deinit();

    var diags = DiagnosticCollection.init(allocator);
    defer diags.deinit();

    const config = Config{
        .rules = .{
            .no_anytype_io_params = .{},
        },
    };

    var ctx = RuleContext{
        .allocator = allocator,
        .file = &file,
        .config = config,
        .ignores = &ignores,
        .diagnostics = &diags,
    };

    try run(&ctx);
    return diags.items.items.len;
}
