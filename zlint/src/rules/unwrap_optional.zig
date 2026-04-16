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

/// ZAI007: Detect optional unwrap (.?) patterns
pub fn run(ctx: *RuleContext) !void {
    if (ctx.shouldSkipFile()) return;

    var severity = Severity.warning;
    if (ctx.config.rules.unwrap_optional) |cfg| {
        severity = Severity.fromString(cfg.base.severity) orelse Severity.warning;
    }

    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        if (tag != .unwrap_optional) continue;

        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (ctx.shouldSkipNode(node)) continue;

        ctx.traceNodeBestEffort(2, node, "match");
        try AstUtils.addDiagnosticAtNode(
            ctx,
            rule_ids.unwrap_optional,
            severity,
            node,
            "optional unwrap (.?) may panic - consider explicit null handling with orelse",
        );
    }
}

fn expectRuleHitsWithAllocator(
    allocator: std.mem.Allocator,
    source: []const u8,
    path: []const u8,
    expected: usize,
) !void {
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
        .path = path,
        .content = content,
        .ast = ast,
    };

    var ignores = try IgnoreDirectives.parse(allocator, source);
    defer ignores.deinit();

    var diagnostics = DiagnosticCollection.init(allocator);
    defer diagnostics.deinit();

    const cfg = Config{
        .rules = .{
            .unwrap_optional = .{},
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
        try std.testing.expectEqualStrings(rule_ids.unwrap_optional, diag.rule_id);
        try std.testing.expectEqual(Severity.warning, diag.severity);
    }
}

test "detects optional unwrap" {
    const source =
        \\fn demo(maybe: ?u8) u8 {
        \\    return maybe.?;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, "src/sample.zig", 1);
}

test "does not detect explicit orelse handling" {
    const source =
        \\fn demo(maybe: ?u8) u8 {
        \\    return maybe orelse 0;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, "src/sample.zig", 0);
}

test "skips test files by default" {
    const source =
        \\fn demo(maybe: ?u8) u8 {
        \\    return maybe.?;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, "src/sample_test.zig", 0);
}
