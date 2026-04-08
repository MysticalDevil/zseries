const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");
const names = @import("../ast/names.zig");
const rule_ids = @import("../rule_ids.zig");

/// Check for doNotOptimizeAway usage
pub fn run(ctx: *RuleContext) !void {
    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    // Get rule config
    var severity = Severity.err;

    if (ctx.config.rules.no_do_not_optimize_away) |config| {
        severity = Severity.fromString(config.base.severity) orelse Severity.err;
    }

    // Build alias map for this file
    var alias_map = std.StringHashMap([]const u8).init(ctx.allocator);
    defer alias_map.deinit();

    // Find aliases like: const mem = std.mem;
    // or: const dna = std.mem.doNotOptimizeAway;
    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (tag == .simple_var_decl) {
            try extractAlias(ast, node, &alias_map);
        }
    }

    // Find all function calls
    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (tag == .call or tag == .call_comma) {
            try checkCall(ctx, node, severity, &alias_map);
        }
    }
}

fn extractAlias(ast: std.zig.Ast, node: std.zig.Ast.Node.Index, alias_map: *std.StringHashMap([]const u8)) !void {
    const node_data = ast.nodeData(node);

    // simple_var_decl uses opt_node_and_opt_node: { type, init }
    const init_node = node_data.opt_node_and_opt_node[1];
    if (init_node == .none) return;

    const init_idx = @intFromEnum(init_node);

    // Get variable name from main_token (skip 'const' token)
    const tokens = ast.nodes.items(.main_token);
    const var_token = tokens[@intFromEnum(node)] + 1;
    const var_name = ast.tokenSlice(var_token);

    // Check if init is std.mem or std.mem.doNotOptimizeAway
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(alias_map.allocator);

    const init_idx_enum: std.zig.Ast.Node.Index = @enumFromInt(init_idx);
    if (try names.extractPath(ast, init_idx_enum, &buf, alias_map.allocator)) |path| {
        if (std.mem.eql(u8, path, "std.mem") or std.mem.eql(u8, path, "std.mem.doNotOptimizeAway")) {
            try alias_map.put(var_name, path);
        }
    }
}

fn checkCall(
    ctx: *RuleContext,
    node: std.zig.Ast.Node.Index,
    severity: Severity,
    alias_map: *std.StringHashMap([]const u8),
) !void {
    const ast = ctx.file.ast;
    const node_data = ast.nodeData(node);

    // call uses node_and_extra: { callee, extra_data }
    const callee = node_data.node_and_extra[0];

    // Check if callee is doNotOptimizeAway
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(ctx.allocator);

    var is_violation = false;

    // Direct call: std.mem.doNotOptimizeAway
    if (try names.extractPath(ast, callee, &buf, ctx.allocator)) |path| {
        if (std.mem.eql(u8, path, "std.mem.doNotOptimizeAway")) {
            is_violation = true;
        }
    }

    // Check for alias usage
    if (!is_violation) {
        const base = names.getBaseIdentifier(ast, callee) orelse return;

        if (alias_map.get(base)) |aliased_path| {
            // Check if it's mem.doNotOptimizeAway where mem is aliased to std.mem
            if (std.mem.eql(u8, aliased_path, "std.mem")) {
                // Check if field access is doNotOptimizeAway
                const tags = ast.nodes.items(.tag);
                if (tags[@intFromEnum(callee)] == .field_access) {
                    const tokens = ast.nodes.items(.main_token);
                    const field_token = tokens[@intFromEnum(callee)];
                    const field_name = ast.tokenSlice(field_token);
                    if (std.mem.eql(u8, field_name, "doNotOptimizeAway")) {
                        is_violation = true;
                    }
                }
            }
            // Direct alias to std.mem.doNotOptimizeAway
            else if (std.mem.eql(u8, aliased_path, "std.mem.doNotOptimizeAway")) {
                is_violation = true;
            }
        }
    }

    if (is_violation) {
        const loc = locations.getNodeLocation(ast, node, ctx.file.content);

        try ctx.addDiagnostic(
            rule_ids.no_do_not_optimize_away,
            severity,
            loc.line,
            loc.column,
            "forbidden call to std.mem.doNotOptimizeAway",
        );
    }
}
