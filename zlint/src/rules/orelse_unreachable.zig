const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const AstUtils = @import("utils.zig").AstUtils;
const rule_ids = @import("../rule_ids.zig");

/// ZAI006: Detect orelse unreachable patterns
pub fn run(ctx: *RuleContext) !void {
    if (ctx.shouldSkipFile()) return;

    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        if (tag != .@"orelse") continue;

        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (ctx.shouldSkipNode(node)) continue;

        ctx.traceNodeBestEffort(2, node, "inspect");
        const rhs = AstUtils.getRhs(ast, node);
        if (!AstUtils.isNodeTag(ast, rhs, .unreachable_literal)) continue;

        ctx.traceNodeBestEffort(2, node, "match");
        try AstUtils.addDiagnosticAtNode(
            ctx,
            rule_ids.orelse_unreachable,
            Severity.err,
            node,
            "orelse unreachable suppresses null handling - use proper null handling instead",
        );
    }
}

fn expectRuleHitsWithAllocator(allocator: std.mem.Allocator, source: []const u8, expected: usize) !void {
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
        .path = "src/sample.zig",
        .content = content,
        .ast = ast,
    };

    var ignores = try IgnoreDirectives.parse(allocator, source);
    defer ignores.deinit();

    var diagnostics = DiagnosticCollection.init(allocator);
    defer diagnostics.deinit();

    const cfg = Config{
        .rules = .{
            .orelse_unreachable = .{},
        },
    };

    var ctx = RuleContext{
        .allocator = allocator,
        .file = &file,
        .config = cfg,
        .ignores = &ignores,
        .diagnostics = &diagnostics,
    };

    try run(&ctx);

    try std.testing.expectEqual(expected, diagnostics.items.items.len);
    for (diagnostics.items.items) |diag| {
        try std.testing.expectEqualStrings(rule_ids.orelse_unreachable, diag.rule_id);
        try std.testing.expectEqual(Severity.err, diag.severity);
    }
}

test "detects orelse unreachable" {
    const source =
        \\fn demo(maybe: ?u8) u8 {
        \\    return maybe orelse unreachable;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 1);
}

test "does not detect normal orelse value" {
    const source =
        \\fn demo(maybe: ?u8) u8 {
        \\    return maybe orelse 0;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 0);
}
