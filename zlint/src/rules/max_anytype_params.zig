const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");
const rule_ids = @import("../rule_ids.zig");

/// Check for too many anytype parameters in functions
pub fn run(ctx: *RuleContext) !void {
    if (ctx.shouldSkipFile()) return;

    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    // Get rule config
    var severity = Severity.err;
    var max_anytype: usize = 2;

    if (ctx.config.rules.max_anytype_params) |config| {
        severity = Severity.fromString(config.base.severity) orelse Severity.err;
        max_anytype = config.max;
    }

    for (tags, 0..) |tag, i| {
        if (tag != .fn_decl) continue;
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (ctx.shouldSkipNode(node)) continue;
        try checkFnDecl(ctx, node, severity, max_anytype);
    }
}

fn checkFnDecl(
    ctx: *RuleContext,
    node: std.zig.Ast.Node.Index,
    severity: Severity,
    max_anytype: usize,
) !void {
    const ast = ctx.file.ast;
    const node_data = ast.nodeData(node);

    // fn_decl uses node_and_node: { proto, body }
    const proto_node = node_data.node_and_node[0];

    const tags = ast.nodes.items(.tag);

    // Get function prototype
    if (tags[@intFromEnum(proto_node)] != .fn_proto and
        tags[@intFromEnum(proto_node)] != .fn_proto_multi)
    {
        return;
    }

    // Count anytype parameters
    const anytype_count = countAnytypeParams(ast, proto_node, ctx.file.content);

    if (anytype_count > max_anytype) {
        const loc = locations.getNodeLocation(ast, node, ctx.file.content);

        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "function has {d} anytype params, max allowed is {d}", .{
            anytype_count,
            max_anytype,
        });

        try ctx.addDiagnostic(
            rule_ids.max_anytype_params,
            severity,
            loc.line,
            loc.column,
            msg,
        );
    }
}

fn countAnytypeParams(ast: std.zig.Ast, proto_node: std.zig.Ast.Node.Index, source: []const u8) usize {
    const first = ast.firstToken(proto_node);
    const last = ast.lastToken(proto_node);
    const start = ast.tokenStart(first);
    const end = ast.tokenStart(last) + @as(u32, @intCast(ast.tokenSlice(last).len));
    if (end <= start or end > source.len) return 0;

    const sig = source[start..end];
    var i: usize = 0;
    var count: usize = 0;
    while (i < sig.len) : (i += 1) {
        if (i + "anytype".len > sig.len) break;
        if (!std.mem.eql(u8, sig[i .. i + "anytype".len], "anytype")) continue;

        const left_ok = i == 0 or !isIdentChar(sig[i - 1]);
        const right_idx = i + "anytype".len;
        const right_ok = right_idx >= sig.len or !isIdentChar(sig[right_idx]);
        if (left_ok and right_ok) count += 1;
    }
    return count;
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}
