const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");
const names = @import("../ast/names.zig");

/// Check for discarded values: `_ = xxx;`
pub fn run(ctx: *RuleContext) !void {
    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    // Get rule config
    var severity = Severity.err;
    var strict = true;
    var allow_names: []const []const u8 = &.{ "deinit", "free" };

    if (ctx.config.rules.discarded_result) |config| {
        severity = Severity.fromString(config.base.severity) orelse Severity.err;
        strict = config.strict;
        if (config.allow_names.len > 0) {
            allow_names = config.allow_names;
        }
    }

    // Find all assignment expressions
    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);

        if (tag == .assign) {
            try checkAssignment(ctx, node, severity, strict, allow_names);
        }
    }
}

fn checkAssignment(
    ctx: *RuleContext,
    node: std.zig.Ast.Node.Index,
    severity: Severity,
    strict: bool,
    allow_names: []const []const u8,
) !void {
    const ast = ctx.file.ast;
    const node_data = ast.nodeData(node);

    // assign uses node_and_node: { lhs, rhs }
    const lhs = node_data.node_and_node[0];
    const rhs = node_data.node_and_node[1];

    // Check if left side is `_`
    if (!isUnderscore(ast, lhs)) return;

    // Skip simple identifier discards like `_ = unused_param;`
    // These are intentional patterns to silence unused parameter warnings
    if (isIdentifier(ast, rhs)) return;

    // In strict mode, always report
    if (!strict) {
        // TODO: Non-strict mode logic
    }

    // Check allowlist
    if (try checkAllowlist(ast, rhs, allow_names, ctx.allocator)) return;

    const loc = locations.getNodeLocation(ast, node, ctx.file.content);

    try ctx.addDiagnostic(
        "discarded-result",
        severity,
        loc.line,
        loc.column,
        "discarded value via '_ = ...;'",
    );
}

fn isUnderscore(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) bool {
    const tags = ast.nodes.items(.tag);
    if (tags[@intFromEnum(node)] != .identifier) return false;

    const tokens = ast.nodes.items(.main_token);
    const token = tokens[@intFromEnum(node)];
    const name = ast.tokenSlice(token);

    return std.mem.eql(u8, name, "_");
}

fn isIdentifier(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) bool {
    const tags = ast.nodes.items(.tag);
    return tags[@intFromEnum(node)] == .identifier;
}

fn checkAllowlist(ast: std.zig.Ast, node: std.zig.Ast.Node.Index, allow_names: []const []const u8, allocator: std.mem.Allocator) !bool {
    // Get the function name being called
    const fn_name = names.getBaseIdentifier(ast, node) orelse return false;
    _ = allocator;

    for (allow_names) |allowed| {
        if (std.mem.eql(u8, fn_name, allowed)) return true;
    }

    return false;
}
