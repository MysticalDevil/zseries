const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");

/// ZAI007: Detect use of global allocator in library functions
/// This catches: std.heap.page_allocator, std.testing.allocator in non-test code
/// Excludes: main, test blocks, examples
pub fn run(ctx: *RuleContext) !void {
    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    // Skip if this is a test file or main file
    if (isTestOrMainFile(ctx.file.path)) return;

    // Find all function declarations
    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);

        switch (tag) {
            .fn_decl => {
                if (!isEntryPointFunction(ast, node)) {
                    try checkFunctionForGlobalAlloc(ctx, node);
                }
            },
            else => {},
        }
    }
}

fn isTestOrMainFile(path: []const u8) bool {
    // Check if path suggests test or main
    if (std.mem.endsWith(u8, path, "_test.zig")) return true;
    if (std.mem.endsWith(u8, path, "/main.zig")) return true;
    if (std.mem.endsWith(u8, path, "/test.zig")) return true;
    if (std.mem.indexOf(u8, path, "/test/") != null) return true;
    if (std.mem.indexOf(u8, path, "/example") != null) return true;
    return false;
}

fn isEntryPointFunction(ast: std.zig.Ast, fn_node: std.zig.Ast.Node.Index) bool {
    const tokens = ast.nodes.items(.main_token);
    const fn_tok = tokens[@intFromEnum(fn_node)];

    // Get function name
    const name_tok = fn_tok + 1; // fn keyword + 1 = name
    const name = ast.tokenSlice(name_tok);

    return std.mem.eql(u8, name, "main") or
        std.mem.eql(u8, name, "test") or
        std.mem.startsWith(u8, name, "test_");
}

fn checkFunctionForGlobalAlloc(ctx: *RuleContext, fn_node: std.zig.Ast.Node.Index) !void {
    const ast = ctx.file.ast;

    // Get function body
    const body = ast.nodeData(fn_node).node_and_node[1];

    // Check for global allocator usage in function body
    try checkNodeForGlobalAlloc(ctx, ast, body, fn_node);
}

fn checkNodeForGlobalAlloc(ctx: *RuleContext, ast: std.zig.Ast, node: std.zig.Ast.Node.Index, fn_node: std.zig.Ast.Node.Index) !void {
    _ = fn_node;
    const tags = ast.nodes.items(.tag);
    const tag = tags[@intFromEnum(node)];

    // Check for field access like std.heap.page_allocator
    if (tag == .field_access) {
        const path = try getFieldAccessPath(ast, node, ctx.allocator);
        defer ctx.allocator.free(path);

        if (isGlobalAllocatorPath(path)) {
            const loc = locations.getNodeLocation(ast, node, ctx.file.content);
            try ctx.addDiagnostic(
                "ZAI007",
                Severity.err,
                loc.line,
                loc.column,
                "using global allocator in library function - accept allocator as parameter instead",
            );
        }
    }

    // TODO: Recurse into child nodes to check entire function body
    // For now, we catch direct usages
}

fn getFieldAccessPath(ast: std.zig.Ast, node: std.zig.Ast.Node.Index, allocator: std.mem.Allocator) ![]const u8 {
    // Build full path from nested field access
    var parts = std.ArrayList([]const u8).empty;
    defer parts.deinit(allocator);

    var current = node;
    while (true) {
        const tag = ast.nodeTag(current);

        if (tag == .field_access) {
            const data = ast.nodeData(current);
            const field_tok = data.node_and_token[1];
            const field_name = ast.tokenSlice(field_tok);
            try parts.append(allocator, field_name);

            current = data.node_and_token[0];
        } else if (tag == .identifier) {
            const tokens = ast.nodes.items(.main_token);
            const tok = tokens[@intFromEnum(current)];
            const name = ast.tokenSlice(tok);
            try parts.append(allocator, name);
            break;
        } else {
            break;
        }
    }

    // Reverse and join
    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);

    var i: usize = parts.items.len;
    while (i > 0) {
        i -= 1;
        try result.appendSlice(allocator, parts.items[i]);
        if (i > 0) {
            try result.append(allocator, '.');
        }
    }

    return result.toOwnedSlice(allocator);
}

fn isGlobalAllocatorPath(path: []const u8) bool {
    return std.mem.eql(u8, path, "std.heap.page_allocator") or
        std.mem.eql(u8, path, "std.testing.allocator") or
        std.mem.eql(u8, path, "std.heap.c_allocator") or
        std.mem.endsWith(u8, path, ".page_allocator") or
        std.mem.endsWith(u8, path, ".c_allocator");
}
