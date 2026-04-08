const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");
const rule_ids = @import("../rule_ids.zig");

const feature_bins = 64;
const min_similarity_default = 0.85;

const BlockShape = struct {
    line: usize,
    stmt_count: usize,
    token_count: usize,
    exact_sig: u64,
    features: [feature_bins]u32,
};

const BlockMatch = struct {
    line: usize,
    similarity: f64,
};

pub fn run(ctx: *RuleContext) !void {
    if (ctx.shouldSkipFile()) return;

    var severity = Severity.warning;
    var min_lines: usize = 5;
    var min_statements: usize = 3;
    if (ctx.config.rules.duplicated_code) |cfg| {
        severity = Severity.fromString(cfg.base.severity) orelse Severity.warning;
        min_lines = cfg.min_lines;
        min_statements = cfg.min_statements;
    }

    const min_similarity = min_similarity_default;
    var seen = std.ArrayList(BlockShape).empty;
    defer seen.deinit(ctx.allocator);

    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);
    var stmt_buf: [2]std.zig.Ast.Node.Index = undefined;

    for (tags, 0..) |tag, i| {
        if (!isBlockTag(tag)) continue;
        const block: std.zig.Ast.Node.Index = @enumFromInt(i);
        const statements = ast.blockStatements(&stmt_buf, block) orelse continue;
        if (statements.len < min_statements) continue;

        const line_span = lineSpan(ast, ctx.file.content, block);
        if (line_span < min_lines) continue;

        const shape = buildBlockShape(ast, ctx.file.content, block, statements);
        if (findBestMatch(seen.items, shape, min_similarity)) |match| {
            const loc = locations.getNodeLocation(ast, block, ctx.file.content);
            var msg_buf: [220]u8 = undefined;
            const msg = try std.fmt.bufPrint(
                &msg_buf,
                "possible duplicate block structure ({d:.1}% similarity) with earlier block at line {d}",
                .{ match.similarity * 100.0, match.line },
            );
            try ctx.addDiagnostic(rule_ids.duplicated_code, severity, loc.line, loc.column, msg);
        }

        try seen.append(ctx.allocator, shape);
    }
}

fn buildBlockShape(
    ast: std.zig.Ast,
    source: []const u8,
    block: std.zig.Ast.Node.Index,
    statements: []const std.zig.Ast.Node.Index,
) BlockShape {
    const loc = locations.getNodeLocation(ast, block, source);
    var features: [feature_bins]u32 = [_]u32{0} ** feature_bins;
    var token_count: usize = 0;

    for (statements) |stmt| {
        const stmt_tag: u16 = @intFromEnum(ast.nodeTag(stmt));
        const stmt_bucket = featureBucket(stmt_tag);
        features[stmt_bucket] +|= 3;

        const first = ast.firstToken(stmt);
        const last = ast.lastToken(stmt);
        var tok = first;
        while (tok <= last) : (tok += 1) {
            const tok_tag = ast.tokenTag(tok);
            const norm = normalizeTokenTag(tok_tag);
            const tok_bucket = featureBucket(norm);
            features[tok_bucket] +|= 1;
            token_count += 1;
        }
    }

    return .{
        .line = loc.line,
        .stmt_count = statements.len,
        .token_count = token_count,
        .exact_sig = blockSignature(ast, statements),
        .features = features,
    };
}

fn findBestMatch(seen: []const BlockShape, current: BlockShape, min_similarity: f64) ?BlockMatch {
    var best_score: f64 = 0.0;
    var best_line: usize = 0;

    for (seen) |candidate| {
        const score = similarityScore(candidate, current);
        if (score > best_score) {
            best_score = score;
            best_line = candidate.line;
        }
    }

    if (best_score < min_similarity) return null;
    return .{ .line = best_line, .similarity = best_score };
}

fn similarityScore(a: BlockShape, b: BlockShape) f64 {
    if (a.exact_sig == b.exact_sig) return 1.0;

    const stmt_diff = if (a.stmt_count >= b.stmt_count) a.stmt_count - b.stmt_count else b.stmt_count - a.stmt_count;
    if (stmt_diff > 1) return 0.0;
    if (a.token_count == 0 or b.token_count == 0) return 0.0;

    var dot: f64 = 0.0;
    var norm_a: f64 = 0.0;
    var norm_b: f64 = 0.0;

    for (0..feature_bins) |i| {
        const av = @as(f64, @floatFromInt(a.features[i]));
        const bv = @as(f64, @floatFromInt(b.features[i]));
        dot += av * bv;
        norm_a += av * av;
        norm_b += bv * bv;
    }

    if (norm_a == 0.0 or norm_b == 0.0) return 0.0;
    return dot / (@sqrt(norm_a) * @sqrt(norm_b));
}

fn featureBucket(value: u16) usize {
    const mixed = @as(usize, value) * 1315423911;
    return mixed % feature_bins;
}

fn isBlockTag(tag: std.zig.Ast.Node.Tag) bool {
    return switch (tag) {
        .block, .block_semicolon, .block_two, .block_two_semicolon => true,
        else => false,
    };
}

fn lineSpan(ast: std.zig.Ast, source: []const u8, node: std.zig.Ast.Node.Index) usize {
    const first = ast.firstToken(node);
    const last = ast.lastToken(node);
    const start_loc = locations.getTokenLocation(ast, first, source);
    const end_loc = locations.getTokenLocation(ast, last, source);
    return if (end_loc.line >= start_loc.line) end_loc.line - start_loc.line + 1 else 1;
}

fn blockSignature(ast: std.zig.Ast, statements: []const std.zig.Ast.Node.Index) u64 {
    var hasher = std.hash.Wyhash.init(0);

    for (statements) |stmt| {
        const tag_val: u16 = @intFromEnum(ast.nodeTag(stmt));
        hasher.update(std.mem.asBytes(&tag_val));

        const first = ast.firstToken(stmt);
        const last = ast.lastToken(stmt);
        var tok = first;
        while (tok <= last) : (tok += 1) {
            const tok_tag = ast.tokenTag(tok);
            const norm = normalizeTokenTag(tok_tag);
            hasher.update(std.mem.asBytes(&norm));
        }
    }

    return hasher.final();
}

fn normalizeTokenTag(tag: std.zig.Token.Tag) u16 {
    return switch (tag) {
        .identifier => 1,
        .number_literal => 2,
        .char_literal, .multiline_string_literal_line, .string_literal, .invalid => 3,
        else => @as(u16, @intCast(@intFromEnum(tag))) + 100,
    };
}
