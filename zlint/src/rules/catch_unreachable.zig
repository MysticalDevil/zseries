const std = @import("std");
const RuleContext = root.RuleContext;
const Severity = diagnostic.Severity;
const AstUtils = utils.AstUtils;
const rule_ids = @import("../rule_ids.zig");
const root = @import("root.zig");
const diagnostic = @import("../diagnostic.zig");
const utils = @import("utils.zig");
const source_file = @import("../source_file.zig");
const ignore_directives = @import("../ignore_directives.zig");
const config = @import("../config.zig");

/// ZAI005: Detect catch unreachable patterns
pub fn run(ctx: *RuleContext) !void {
    if (ctx.shouldSkipFile()) return;

    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);

        if (ctx.shouldSkipNode(node)) continue;

        if (tag == .@"catch") {
            ctx.traceNodeBestEffort(2, node, "inspect");
            const rhs = AstUtils.getRhs(ast, node);
            if (AstUtils.isNodeTag(ast, rhs, .unreachable_literal)) {
                ctx.traceNodeBestEffort(2, node, "match");
                try AstUtils.addDiagnosticAtNode(
                    ctx,
                    rule_ids.catch_unreachable,
                    Severity.err,
                    node,
                    "catch unreachable suppresses error handling - use proper error handling instead",
                );
            }
        }
    }
}

fn expectRuleHitsWithAllocator(allocator: std.mem.Allocator, source: []const u8, expected: usize) !void {
    const content = try allocator.dupeZ(u8, source);
    defer allocator.free(content);

    var ast = try std.zig.Ast.parse(allocator, content, .zig);
    defer ast.deinit(allocator);

    const SourceFile = source_file.SourceFile;
    const IgnoreDirectives = ignore_directives.IgnoreDirectives;
    const DiagnosticCollection = diagnostic.DiagnosticCollection;
    const Config = config.Config;

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
            .catch_unreachable = .{},
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
        try std.testing.expectEqualStrings(rule_ids.catch_unreachable, diag.rule_id);
        try std.testing.expectEqual(Severity.err, diag.severity);
    }
}

test "detects catch unreachable" {
    const source =
        \\fn fallible() anyerror!u8 { return 1; }
        \\fn demo() u8 {
        \\    return fallible() catch unreachable;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 1);
}

test "does not detect catch return" {
    const source =
        \\fn fallible() anyerror!u8 { return 1; }
        \\fn demo() u8 {
        \\    return fallible() catch return 0;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, 0);
}
