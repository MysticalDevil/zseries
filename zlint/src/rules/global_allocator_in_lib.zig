const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");
const names = @import("../ast/names.zig");
const rule_ids = @import("../rule_ids.zig");

pub fn run(ctx: *RuleContext) !void {
    if (isTestOrMainFile(ctx.file.path)) return;

    var severity = Severity.err;
    if (ctx.config.rules.global_allocator_in_lib) |cfg| {
        severity = Severity.fromString(cfg.base.severity) orelse Severity.err;
    }

    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);
    for (tags, 0..) |tag, i| {
        if (tag != .fn_decl) continue;
        const fn_node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (isEntryPointFunction(ast, fn_node)) continue;
        try checkFunction(ctx, fn_node, severity);
    }
}

fn checkFunction(ctx: *RuleContext, fn_node: std.zig.Ast.Node.Index, severity: Severity) !void {
    const ast = ctx.file.ast;
    const body_node = ast.nodeData(fn_node).node_and_node[1];
    if (@intFromEnum(body_node) == 0) return;

    var path_buf = std.ArrayList(u8).empty;
    defer path_buf.deinit(ctx.allocator);

    const tags = ast.nodes.items(.tag);
    for (tags, 0..) |tag, i| {
        if (tag != .field_access) continue;
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (!isInsideNode(ast, body_node, node)) continue;

        const maybe_path = try names.extractPath(ast, node, &path_buf, ctx.allocator);
        defer if (maybe_path) |p| ctx.allocator.free(p);
        const path = maybe_path orelse continue;
        if (!isGlobalAllocatorPath(path)) continue;

        const loc = locations.getNodeLocation(ast, fn_node, ctx.file.content);
        try ctx.addDiagnostic(
            rule_ids.global_allocator_in_lib,
            severity,
            loc.line,
            loc.column,
            "using global allocator in library function; accept allocator as parameter instead",
        );
        return;
    }
}

fn isInsideNode(ast: std.zig.Ast, parent: std.zig.Ast.Node.Index, node: std.zig.Ast.Node.Index) bool {
    const p_first = ast.firstToken(parent);
    const p_last = ast.lastToken(parent);
    const n_first = ast.firstToken(node);
    const n_last = ast.lastToken(node);
    return n_first >= p_first and n_last <= p_last;
}

fn isGlobalAllocatorPath(path: []const u8) bool {
    return std.mem.eql(u8, path, "std.heap.page_allocator") or
        std.mem.eql(u8, path, "std.heap.c_allocator") or
        std.mem.eql(u8, path, "std.testing.allocator");
}

fn isTestOrMainFile(path: []const u8) bool {
    return std.mem.endsWith(u8, path, "_test.zig") or
        std.mem.endsWith(u8, path, "/main.zig") or
        std.mem.endsWith(u8, path, "/test.zig") or
        std.mem.indexOf(u8, path, "/test/") != null or
        std.mem.indexOf(u8, path, "/tests/") != null or
        std.mem.indexOf(u8, path, "/example/") != null or
        std.mem.indexOf(u8, path, "/examples/") != null;
}

fn isEntryPointFunction(ast: std.zig.Ast, fn_node: std.zig.Ast.Node.Index) bool {
    const tokens = ast.nodes.items(.main_token);
    const fn_token = tokens[@intFromEnum(fn_node)];
    const name = ast.tokenSlice(fn_token + 1);

    return std.mem.eql(u8, name, "main") or
        std.mem.eql(u8, name, "test") or
        std.mem.startsWith(u8, name, "test_");
}
