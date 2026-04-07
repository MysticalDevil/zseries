const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");

/// Check for too many anytype parameters in functions
pub fn run(ctx: *RuleContext) !void {
    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    // Get rule config
    var severity = Severity.err;
    var max_anytype: usize = 2;

    if (ctx.config.rules.max_anytype_params) |config| {
        severity = Severity.fromString(config.base.severity) orelse Severity.err;
        max_anytype = config.max;
    }

    // Find all function declarations
    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);

        switch (tag) {
            .fn_decl => try checkFnDecl(ctx, node, severity, max_anytype),
            else => {},
        }
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
    const anytype_count = try countAnytypeParams(ast, proto_node);

    if (anytype_count > max_anytype) {
        const loc = locations.getNodeLocation(ast, node, ctx.file.content);

        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "function has {d} anytype params, max allowed is {d}", .{
            anytype_count,
            max_anytype,
        });

        try ctx.addDiagnostic(
            "max-anytype-params",
            severity,
            loc.line,
            loc.column,
            msg,
        );
    }
}

fn countAnytypeParams(ast: std.zig.Ast, proto_node: std.zig.Ast.Node.Index) !usize {
    _ = proto_node;

    const count: usize = 0;

    // TODO: Implement proper anytype parameter counting for Zig 0.16
    // This requires walking the function prototype's parameter list
    _ = ast;

    return count;
}
