const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");
const rule_ids = @import("../rule_ids.zig");

pub fn run(ctx: *RuleContext) !void {
    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    var severity = Severity.err;
    if (ctx.config.rules.unused_allocator) |cfg| {
        severity = Severity.fromString(cfg.base.severity) orelse Severity.err;
    }

    for (tags, 0..) |tag, i| {
        if (tag != .fn_decl) continue;
        const fn_node: std.zig.Ast.Node.Index = @enumFromInt(i);
        try checkFunction(ctx, fn_node, severity);
    }
}

fn checkFunction(ctx: *RuleContext, fn_node: std.zig.Ast.Node.Index, severity: Severity) !void {
    const ast = ctx.file.ast;
    const fn_data = ast.nodeData(fn_node);
    const proto_node = fn_data.node_and_node[0];
    const body_node = fn_data.node_and_node[1];
    if (@intFromEnum(body_node) == 0) return;

    var proto_buf: [1]std.zig.Ast.Node.Index = undefined;
    const proto = ast.fullFnProto(&proto_buf, proto_node) orelse return;

    var alloc_params = std.ArrayList([]const u8).empty;
    defer alloc_params.deinit(ctx.allocator);

    for (proto.ast.params) |param_node| {
        if (@intFromEnum(param_node) == 0) continue;
        const tok = ast.nodes.items(.main_token)[@intFromEnum(param_node)];
        const name = ast.tokenSlice(tok);
        if (isAllocatorName(name)) try alloc_params.append(ctx.allocator, name);
    }

    if (alloc_params.items.len == 0) return;

    var discard_tokens = std.AutoHashMap(std.zig.Ast.TokenIndex, void).init(ctx.allocator);
    defer discard_tokens.deinit();
    try collectDiscardTokens(ctx, body_node, &discard_tokens, alloc_params.items);

    for (alloc_params.items) |param_name| {
        if (isParamUsed(ctx, body_node, param_name, &discard_tokens)) continue;

        const loc = locations.getNodeLocation(ast, fn_node, ctx.file.content);
        try ctx.addDiagnostic(
            rule_ids.unused_allocator,
            severity,
            loc.line,
            loc.column,
            "allocator parameter is passed but never used",
        );
    }
}

fn collectDiscardTokens(
    ctx: *RuleContext,
    body_node: std.zig.Ast.Node.Index,
    discard_tokens: *std.AutoHashMap(std.zig.Ast.TokenIndex, void),
    allocator_names: []const []const u8,
) !void {
    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        if (tag != .assign) continue;
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (!isInsideNode(ast, body_node, node)) continue;

        const data = ast.nodeData(node);
        const lhs = data.node_and_node[0];
        const rhs = data.node_and_node[1];
        if (!isUnderscoreIdentifier(ast, lhs)) continue;
        if (ast.nodeTag(rhs) != .identifier) continue;

        const rhs_token = ast.nodes.items(.main_token)[@intFromEnum(rhs)];
        const rhs_name = ast.tokenSlice(rhs_token);
        if (!inList(rhs_name, allocator_names)) continue;

        try discard_tokens.put(rhs_token, {});
    }
}

fn isParamUsed(
    ctx: *RuleContext,
    body_node: std.zig.Ast.Node.Index,
    param_name: []const u8,
    discard_tokens: *const std.AutoHashMap(std.zig.Ast.TokenIndex, void),
) bool {
    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        if (tag != .identifier) continue;
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (!isInsideNode(ast, body_node, node)) continue;

        const token = ast.nodes.items(.main_token)[@intFromEnum(node)];
        if (discard_tokens.contains(token)) continue;
        if (!std.mem.eql(u8, ast.tokenSlice(token), param_name)) continue;
        return true;
    }

    return false;
}

fn isInsideNode(ast: std.zig.Ast, parent: std.zig.Ast.Node.Index, node: std.zig.Ast.Node.Index) bool {
    const p_first = ast.firstToken(parent);
    const p_last = ast.lastToken(parent);
    const n_first = ast.firstToken(node);
    const n_last = ast.lastToken(node);
    return n_first >= p_first and n_last <= p_last;
}

fn isUnderscoreIdentifier(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) bool {
    if (ast.nodeTag(node) != .identifier) return false;
    const token = ast.nodes.items(.main_token)[@intFromEnum(node)];
    return std.mem.eql(u8, ast.tokenSlice(token), "_");
}

fn isAllocatorName(name: []const u8) bool {
    return std.mem.eql(u8, name, "allocator") or
        std.mem.eql(u8, name, "alloc") or
        std.mem.eql(u8, name, "gpa") or
        std.mem.eql(u8, name, "arena") or
        std.mem.endsWith(u8, name, "_allocator") or
        std.mem.endsWith(u8, name, "_alloc");
}

fn inList(name: []const u8, list: []const []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, name, item)) return true;
    }
    return false;
}
