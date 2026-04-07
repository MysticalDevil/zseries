const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");

/// Check for empty or comment-only catch blocks: `catch {}` or `catch { // ... }`
pub fn run(ctx: *RuleContext) !void {
    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);

    // Get rule config
    var severity = Severity.warning;

    if (ctx.config.rules.no_empty_catch) |config| {
        severity = Severity.fromString(config.severity) orelse Severity.warning;
    }

    // Find all catch expressions
    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);

        if (tag == .@"catch") {
            try checkCatchBlock(ctx, node, severity);
        }
    }
}

fn checkCatchBlock(
    ctx: *RuleContext,
    node: std.zig.Ast.Node.Index,
    severity: Severity,
) !void {
    const ast = ctx.file.ast;
    const node_data = ast.nodeData(node);

    // catch uses node_and_node: { lhs, rhs }
    const lhs = node_data.node_and_node[0];
    const rhs = node_data.node_and_node[1];
    _ = lhs;

    const rhs_tag = ast.nodeTag(rhs);

    // Allow unreachable
    if (rhs_tag == .unreachable_literal) return;

    // Allow null identifier
    if (rhs_tag == .identifier) {
        const tokens = ast.nodes.items(.main_token);
        const token = tokens[@intFromEnum(rhs)];
        const name = ast.tokenSlice(token);
        if (std.mem.eql(u8, name, "null")) return;
    }

    // Check blocks for being empty or comment-only
    switch (rhs_tag) {
        .block_two, .block_two_semicolon, .block, .block_semicolon => {
            if (try isEmptyOrCommentOnlyBlock(ast, rhs, ctx.file.content)) {
                const loc = locations.getNodeLocation(ast, node, ctx.file.content);
                try ctx.addDiagnostic(
                    "no-empty-catch",
                    severity,
                    loc.line,
                    loc.column,
                    "empty catch block suppresses error handling",
                );
            }
        },
        else => {},
    }
}

/// Check if a block is empty or contains only comments
fn isEmptyOrCommentOnlyBlock(
    ast: std.zig.Ast,
    block_node: std.zig.Ast.Node.Index,
    source: []const u8,
) !bool {
    const first_tok = ast.firstToken(block_node);
    const last_tok = ast.lastToken(block_node);

    const block_start = ast.tokenStart(first_tok);
    const block_end = ast.tokenStart(last_tok) + @as(u32, @intCast(ast.tokenSlice(last_tok).len));
    const block_content = source[block_start..block_end];

    // Skip opening brace and whitespace after it
    var i: usize = 0;
    if (i < block_content.len and block_content[i] == '{') {
        i += 1;
    }

    // Skip trailing '}'
    var end: usize = block_content.len;
    if (end > 0 and block_content[end - 1] == '}') {
        end -= 1;
    }

    // Check content between { and }
    while (i < end) {
        // Skip whitespace
        while (i < end and std.ascii.isWhitespace(block_content[i])) {
            i += 1;
        }

        if (i >= end) break;

        // Check for comments
        if (i + 1 < end and block_content[i] == '/' and block_content[i + 1] == '/') {
            while (i < end and block_content[i] != '\n') {
                i += 1;
            }
            continue;
        }

        if (i + 1 < end and block_content[i] == '/' and block_content[i + 1] == '*') {
            i += 2;
            while (i + 1 < end) {
                if (block_content[i] == '*' and block_content[i + 1] == '/') {
                    i += 2;
                    break;
                }
                i += 1;
            }
            continue;
        }

        // Found non-comment, non-whitespace content
        // Check if it's just a discard pattern `_ = ...`
        if (isDiscardPattern(block_content[i..], end - i)) {
            return true;
        }

        return false;
    }

    // Only whitespace and/or comments found
    return true;
}

/// Check if the content starts with a discard pattern like `_ = ...`
fn isDiscardPattern(content: []const u8, len: usize) bool {
    var i: usize = 0;

    // Skip leading whitespace
    while (i < len and std.ascii.isWhitespace(content[i])) {
        i += 1;
    }

    // Check for `_`
    if (i >= len or content[i] != '_') return false;
    i += 1;

    // Skip whitespace
    while (i < len and std.ascii.isWhitespace(content[i])) {
        i += 1;
    }

    // Check for `=`
    if (i >= len or content[i] != '=') return false;

    return true;
}
