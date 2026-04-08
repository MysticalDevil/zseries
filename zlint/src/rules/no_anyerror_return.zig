const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");
const rule_ids = @import("../rule_ids.zig");

/// ZAI015: Detect explicit anyerror return types on ordinary function declarations
pub fn run(ctx: *RuleContext) !void {
    if (ctx.shouldSkipFile()) return;

    var severity = Severity.warning;
    if (ctx.config.rules.no_anyerror_return) |cfg| {
        severity = Severity.fromString(cfg.base.severity) orelse Severity.warning;
    }

    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        if (tag != .fn_decl) continue;

        const node: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (ctx.shouldSkipNode(node)) continue;
        ctx.traceNodeBestEffort(2, node, "inspect");
        try checkFnDecl(ctx, node, severity);
    }
}

fn checkFnDecl(ctx: *RuleContext, fn_node: std.zig.Ast.Node.Index, severity: Severity) !void {
    const ast = ctx.file.ast;
    var proto_buf: [1]std.zig.Ast.Node.Index = undefined;
    const proto = ast.fullFnProto(&proto_buf, fn_node) orelse return;
    const return_type = proto.ast.return_type.unwrap() orelse return;
    if (ast.nodeTag(return_type) != .error_union) return;

    const lhs = ast.nodeData(return_type).node_and_node[0];
    if (ast.nodeTag(lhs) != .identifier) return;

    const token = ast.nodes.items(.main_token)[@intFromEnum(lhs)];
    if (!std.mem.eql(u8, ast.tokenSlice(token), "anyerror")) return;

    ctx.traceNodeBestEffort(2, fn_node, "match");
    const loc = locations.getNodeLocation(ast, return_type, ctx.file.content);
    try ctx.addDiagnostic(
        rule_ids.no_anyerror_return,
        severity,
        loc.line,
        loc.column,
        "explicit anyerror return type widens the error set; prefer inferred !T",
    );
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

    var ignores = try IgnoreDirectives.parse(allocator, source);
    defer ignores.deinit();

    var diagnostics = DiagnosticCollection.init(allocator);
    defer diagnostics.deinit();

    const cfg = Config{
        .rules = .{
            .no_anyerror_return = .{},
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
        try std.testing.expectEqualStrings(rule_ids.no_anyerror_return, diag.rule_id);
        try std.testing.expectEqual(Severity.warning, diag.severity);
    }
}

test "detects explicit anyerror return on ordinary function" {
    const source =
        \\fn demo() anyerror!void {
        \\    return;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, "src/sample.zig", 1);
}

test "does not detect inferred error return" {
    const source =
        \\fn demo() !void {
        \\    return;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, "src/sample.zig", 0);
}

test "does not detect function pointer anyerror type" {
    const source =
        \\const Handler = *const fn () anyerror!void;
        \\fn demo(handler: Handler) void {
        \\    _ = handler;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, "src/sample.zig", 0);
}

test "skips test files by default" {
    const source =
        \\fn demo() anyerror!void {
        \\    return;
        \\}
    ;
    try expectRuleHitsWithAllocator(std.testing.allocator, source, "src/sample_test.zig", 0);
}
