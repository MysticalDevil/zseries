const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");
const rule_ids = @import("../rule_ids.zig");

const feature_bins = 64;
const min_similarity_default = 0.96;
const min_tokens_default: usize = 40;
const max_reports_default: usize = 12;
const min_fuzzy_lines_default: usize = 20;
const io_short_line_limit: usize = 12;
const io_min_call_count: usize = 4;
const template_short_line_limit: usize = 16;
const template_similarity_boost: f64 = 0.985;

const BlockShape = struct {
    line: usize,
    line_span: usize,
    stmt_count: usize,
    token_count: usize,
    first_token: std.zig.Ast.TokenIndex,
    last_token: std.zig.Ast.TokenIndex,
    exact_sig: u64,
    io_heavy: bool,
    template_like: bool,
    features: [feature_bins]u32,
};

const BlockMatch = struct {
    line: usize,
    similarity: f64,
    line_span: usize,
    io_heavy: bool,
    template_like: bool,
};

pub fn run(ctx: *RuleContext) !void {
    if (ctx.shouldSkipFile()) return;

    var severity = Severity.warning;
    var min_lines: usize = 8;
    var min_statements: usize = 4;
    var min_tokens: usize = min_tokens_default;
    var min_similarity: f64 = min_similarity_default;
    var max_reports_per_file: usize = max_reports_default;
    var min_fuzzy_lines: usize = min_fuzzy_lines_default;
    if (ctx.config.rules.duplicated_code) |cfg| {
        severity = Severity.fromString(cfg.base.severity) orelse Severity.warning;
        min_lines = cfg.min_lines;
        min_statements = cfg.min_statements;
        min_tokens = cfg.min_tokens;
        min_similarity = @as(f64, @floatFromInt(cfg.min_similarity_percent)) / 100.0;
        max_reports_per_file = cfg.max_reports_per_file;
        min_fuzzy_lines = cfg.min_fuzzy_lines;
    }

    var seen = std.ArrayList(BlockShape).empty;
    defer seen.deinit(ctx.allocator);
    var reports: usize = 0;

    const ast = ctx.file.ast;
    const tags = ast.nodes.items(.tag);
    var stmt_buf: [2]std.zig.Ast.Node.Index = undefined;

    for (tags, 0..) |tag, i| {
        if (!isBlockTag(tag)) continue;
        const block: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (ctx.shouldSkipNode(block)) continue;
        ctx.traceNodeBestEffort(2, block, "inspect");
        const statements = ast.blockStatements(&stmt_buf, block) orelse continue;
        if (statements.len < min_statements) continue;

        const line_span = lineSpan(ast, ctx.file.content, block);
        if (line_span < min_lines) continue;

        const shape = buildBlockShape(ast, ctx.file.path, ctx.file.content, block, statements);
        if (shape.token_count < min_tokens) {
            try seen.append(ctx.allocator, shape);
            continue;
        }

        if (findBestMatch(seen.items, shape, min_similarity, min_fuzzy_lines)) |match| {
            ctx.traceNodeBestEffort(2, block, "match");
            const loc = locations.getNodeLocation(ast, block, ctx.file.content);
            var msg_buf: [220]u8 = undefined;
            const msg = try std.fmt.bufPrint(
                &msg_buf,
                "possible duplicate block structure ({d:.1}% similarity) with earlier block at line {d}",
                .{ match.similarity * 100.0, match.line },
            );
            try ctx.addDiagnostic(rule_ids.duplicated_code, classifySeverity(severity, shape, match), loc.line, loc.column, msg);
            reports += 1;
            if (reports >= max_reports_per_file) return;
        }

        ctx.traceNodeBestEffort(2, block, "record-shape");
        try seen.append(ctx.allocator, shape);
    }
}

fn buildBlockShape(
    ast: std.zig.Ast,
    file_path: []const u8,
    source: []const u8,
    block: std.zig.Ast.Node.Index,
    statements: []const std.zig.Ast.Node.Index,
) BlockShape {
    const loc = locations.getNodeLocation(ast, block, source);
    var features: [feature_bins]u32 = [_]u32{0} ** feature_bins;
    var token_count: usize = 0;
    var io_call_count: usize = 0;
    const block_slice = nodeSlice(ast, source, block);

    for (statements) |stmt| {
        const stmt_tag: u16 = @intFromEnum(ast.nodeTag(stmt));
        const stmt_bucket = featureBucket(stmt_tag);
        features[stmt_bucket] +|= 3;
        if (statementLooksIoHeavy(ast, source, stmt)) io_call_count += 1;

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
        .line_span = lineSpan(ast, source, block),
        .stmt_count = statements.len,
        .token_count = token_count,
        .first_token = ast.firstToken(block),
        .last_token = ast.lastToken(block),
        .exact_sig = blockSignature(ast, statements),
        .io_heavy = io_call_count >= io_min_call_count,
        .template_like = sliceLooksTemplateLike(file_path, block_slice),
        .features = features,
    };
}

fn findBestMatch(seen: []const BlockShape, current: BlockShape, min_similarity: f64, min_fuzzy_lines: usize) ?BlockMatch {
    var best_score: f64 = 0.0;
    var best_line: usize = 0;
    var best_exact = false;

    for (seen) |candidate| {
        if (!isComparable(candidate, current, min_fuzzy_lines)) continue;

        const score = similarityScore(candidate, current);
        if (score > best_score) {
            best_score = score;
            best_line = candidate.line;
            best_exact = candidate.exact_sig == current.exact_sig;
        }
    }

    if (best_exact) {
        for (seen) |candidate| {
            if (candidate.line == best_line) {
                return .{
                    .line = best_line,
                    .similarity = 1.0,
                    .line_span = candidate.line_span,
                    .io_heavy = candidate.io_heavy,
                    .template_like = candidate.template_like,
                };
            }
        }
    }
    if (best_score < min_similarity) return null;
    for (seen) |candidate| {
        if (candidate.line == best_line) {
            return .{
                .line = best_line,
                .similarity = best_score,
                .line_span = candidate.line_span,
                .io_heavy = candidate.io_heavy,
                .template_like = candidate.template_like,
            };
        }
    }
    return null;
}

fn isComparable(a: BlockShape, b: BlockShape, min_fuzzy_lines: usize) bool {
    if (rangesContainEachOther(a, b)) return false;
    if (a.exact_sig == b.exact_sig) return true;
    if ((a.template_like or b.template_like) and similarityFriendlyTemplatePair(a, b)) return true;
    return a.line_span >= min_fuzzy_lines and b.line_span >= min_fuzzy_lines;
}

fn rangesContainEachOther(a: BlockShape, b: BlockShape) bool {
    const a_contains_b = a.first_token <= b.first_token and a.last_token >= b.last_token;
    const b_contains_a = b.first_token <= a.first_token and b.last_token >= a.last_token;
    return a_contains_b or b_contains_a;
}

fn classifySeverity(default_severity: Severity, current: BlockShape, match: BlockMatch) Severity {
    if (default_severity == .help) return .help;
    if (current.template_like or match.template_like) return .help;
    if ((current.io_heavy or match.io_heavy) and
        (current.line_span < io_short_line_limit or match.line_span < io_short_line_limit))
    {
        return .help;
    }
    return default_severity;
}

fn similarityFriendlyTemplatePair(a: BlockShape, b: BlockShape) bool {
    return a.line_span <= template_short_line_limit and b.line_span <= template_short_line_limit;
}

fn statementLooksIoHeavy(ast: std.zig.Ast, source: []const u8, stmt: std.zig.Ast.Node.Index) bool {
    const first = ast.firstToken(stmt);
    const last = ast.lastToken(stmt);
    const start = ast.tokenStart(first);
    const end = ast.tokenStart(last) + @as(u32, @intCast(ast.tokenSlice(last).len));
    if (end <= start or end > source.len) return false;

    const slice = source[start..end];
    return std.mem.indexOf(u8, slice, ".write") != null or
        std.mem.indexOf(u8, slice, ".print") != null or
        std.mem.indexOf(u8, slice, ".read") != null or
        std.mem.indexOf(u8, slice, ".flush") != null;
}

fn sliceLooksTemplateLike(file_path: []const u8, slice: []const u8) bool {
    const markers = [_][]const u8{
        "ctx.addDiagnostic",
        "locations.getNodeLocation",
        "locations.getTokenLocation",
        "Severity.fromString",
        "parseBaseRuleConfig",
        "rule_node.get(",
        "root.get(",
        "scan_node.get(",
        "output_node.get(",
        "rules_cfg.",
        "configFail(",
        "std.fmt.bufPrint",
        "var msg_buf",
        "alias_map.get(",
        "names.extractPath",
        "fullContainerField",
        "ast.nodes.items(",
        "ast.nodeTag(",
        "ast.firstToken(",
        "ast.lastToken(",
        "ast.tokenStart(",
        "ast.tokenTag(",
        "ast.blockStatements(",
        "fullCall(",
        "data.node_and_token",
        "data.node_and_node",
        "std.hash.Wyhash.init(",
        "normalizeTokenTag(",
        "best_score",
        "best_line",
        ".template_like =",
        "b.createModule(",
        "b.addTest(",
        "b.addSystemCommand(",
        "b.resolveTargetQuery(",
        "writeHeader(",
        "writeHeading(",
        "writeBullet(",
        "writeExample(",
        "out.toOwnedSlice()",
        "buf.putText(",
        "std.Io.Writer.Allocating = .init(",
    };

    var hits: usize = 0;
    for (markers) |marker| {
        if (std.mem.indexOf(u8, slice, marker) != null) hits += 1;
    }
    if (hits >= 1) return true;
    if (pathHas(file_path, "/cli/help.zig")) return true;
    if (std.mem.endsWith(u8, file_path, "/build.zig") or std.mem.eql(u8, file_path, "build.zig")) return true;
    if (looksLikeLexerParserBoilerplate(file_path, slice)) return true;
    if (looksLikeMiddlewareFieldMapping(file_path, slice)) return true;
    if (looksLikeWidgetBoilerplate(file_path, slice)) return true;
    if (looksLikeHttpServerBoilerplate(file_path, slice)) return true;
    if (looksLikeFilesystemRetryBoilerplate(file_path, slice)) return true;
    if (looksLikeThirdPartyMappingBoilerplate(file_path, slice)) return true;
    return false;
}

fn looksLikeLexerParserBoilerplate(file_path: []const u8, slice: []const u8) bool {
    if (!std.mem.endsWith(u8, file_path, "/lexer.zig") and !std.mem.endsWith(u8, file_path, "/parser.zig")) {
        return false;
    }

    const markers = [_][]const u8{
        "const start_line = self.line",
        "const start_col = self.column",
        "const start_pos = self.pos",
        "self.current_token.type",
        "try self.expect(",
        "try self.advance()",
        "try self.skipNewlines()",
        "return self.tokenFromRange(",
        "return self.tokenFromText(",
        "return Value.",
        "try self.parseValue()",
    };
    return countMarkerHits(slice, &markers) >= 2;
}

fn looksLikeMiddlewareFieldMapping(file_path: []const u8, slice: []const u8) bool {
    if (!std.mem.endsWith(u8, file_path, "/middleware.zig")) return false;

    const markers = [_][]const u8{
        "self.config.fields",
        "fields.append(field.Field.",
        "req.getHeader(",
        "self.logger.log(",
        "Level.info",
    };
    return countMarkerHits(slice, &markers) >= 3;
}

fn looksLikeWidgetBoilerplate(file_path: []const u8, slice: []const u8) bool {
    if (!pathHas(file_path, "/widgets/")) return false;

    const markers = [_][]const u8{
        "buf.putText(",
        "terminal.",
        "input_mod.readEvent(",
        "card.drawFn(",
        "self.sections.items",
    };
    return countMarkerHits(slice, &markers) >= 2;
}

fn looksLikeHttpServerBoilerplate(file_path: []const u8, slice: []const u8) bool {
    if (!std.mem.endsWith(u8, file_path, "/server.zig")) return false;

    const markers = [_][]const u8{
        "http.Server",
        "request.respond(",
        "receiveHead()",
        "self.handleRequest(&request)",
        "ctx.response_headers.iterator()",
        "extra_headers[header_count]",
    };
    return countMarkerHits(slice, &markers) >= 2;
}

fn looksLikeFilesystemRetryBoilerplate(file_path: []const u8, slice: []const u8) bool {
    if (!pathHas(file_path, "/backend/")) return false;

    const markers = [_][]const u8{
        "options.max_attempts",
        "try openParent(",
        "try makeName(",
        "allocator.free(name)",
        "parent_copy",
        "full_path",
        "error.PathAlreadyExists",
    };
    return countMarkerHits(slice, &markers) >= 4;
}

fn looksLikeThirdPartyMappingBoilerplate(file_path: []const u8, slice: []const u8) bool {
    if (!pathHas(file_path, "/thirdparty/")) return false;

    const markers = [_][]const u8{
        ".issuer =",
        ".account_name =",
        ".digits =",
        ".period =",
        ".algorithm =",
        ".source_format =",
        "std.json",
        "entries.append(allocator, .{",
    };
    return countMarkerHits(slice, &markers) >= 4;
}

fn countMarkerHits(slice: []const u8, markers: []const []const u8) usize {
    var hits: usize = 0;
    for (markers) |marker| {
        if (std.mem.indexOf(u8, slice, marker) != null) hits += 1;
    }
    return hits;
}

fn pathHas(path: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, path, needle) != null;
}

fn nodeSlice(ast: std.zig.Ast, source: []const u8, node: std.zig.Ast.Node.Index) []const u8 {
    const first = ast.firstToken(node);
    const last = ast.lastToken(node);
    const start = ast.tokenStart(first);
    const end = ast.tokenStart(last) + @as(u32, @intCast(ast.tokenSlice(last).len));
    if (end <= start or end > source.len) return "";
    return source[start..end];
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
    var score = dot / (@sqrt(norm_a) * @sqrt(norm_b));
    if (a.template_like and b.template_like and score < template_similarity_boost) {
        score = template_similarity_boost;
    }
    return score;
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

test "duplicated_code ignores short io-heavy write sequences" {
    const allocator = std.testing.allocator;
    const source =
        \\const std = @import("std");
        \\pub fn emitA(writer: anytype, a: []const u8, b: []const u8) !void {
        \\    try writer.writeByte(0xAA);
        \\    try writer.writeInt(u16, @intCast(a.len), .little);
        \\    try writer.writeAll(a);
        \\    try writer.writeInt(u16, @intCast(b.len), .little);
        \\    try writer.writeAll(b);
        \\}
        \\pub fn emitB(out: anytype, x: []const u8, y: []const u8) !void {
        \\    try out.writeByte(0xAA);
        \\    try out.writeInt(u16, @intCast(x.len), .little);
        \\    try out.writeAll(x);
        \\    try out.writeInt(u16, @intCast(y.len), .little);
        \\    try out.writeAll(y);
        \\}
    ;

    const result = try runRuleOnSource(allocator, source);
    defer result.diags.deinit();
    try std.testing.expectEqual(@as(usize, 0), result.summary.warnings);
    try std.testing.expectEqual(@as(usize, 1), result.summary.helps);
}

test "duplicated_code reports long io-heavy write sequences" {
    const allocator = std.testing.allocator;
    const source =
        \\const std = @import("std");
        \\pub fn emitPacketA(writer: anytype, payload: []const u8, meta: []const u8) !void {
        \\    try writer.writeByte(0xAA);
        \\    try writer.writeByte(0x55);
        \\    try writer.writeInt(u16, @intCast(payload.len), .little);
        \\    try writer.writeAll(payload);
        \\    try writer.writeByte(0x01);
        \\    try writer.writeInt(u16, @intCast(meta.len), .little);
        \\    try writer.writeAll(meta);
        \\    try writer.writeByte(0xFF);
        \\    try writer.writeInt(u32, checksum(payload, meta), .little);
        \\}
        \\pub fn emitPacketB(out: anytype, body: []const u8, info: []const u8) !void {
        \\    try out.writeByte(0xAA);
        \\    try out.writeByte(0x55);
        \\    try out.writeInt(u16, @intCast(body.len), .little);
        \\    try out.writeAll(body);
        \\    try out.writeByte(0x01);
        \\    try out.writeInt(u16, @intCast(info.len), .little);
        \\    try out.writeAll(info);
        \\    try out.writeByte(0xFF);
        \\    try out.writeInt(u32, checksum(body, info), .little);
        \\}
        \\fn checksum(a: []const u8, b: []const u8) u32 {
        \\    return @intCast(a.len + b.len);
        \\}
    ;

    const result = try runRuleOnSource(allocator, source);
    defer result.diags.deinit();
    try std.testing.expectEqual(@as(usize, 1), result.summary.warnings);
    try std.testing.expectEqual(@as(usize, 0), result.summary.helps);
}

test "duplicated_code downgrades rule skeleton duplicates to help" {
    const allocator = std.testing.allocator;
    const source =
        \\const std = @import("std");
        \\const RuleContext = struct {};
        \\fn checkOne(ctx: *RuleContext, node: usize) !void {
        \\    if (node == 0) return;
        \\    const loc_line = node;
        \\    const loc_col = node + 1;
        \\    _ = ctx;
        \\    _ = loc_line;
        \\    _ = loc_col;
        \\    try emitDiag("one");
        \\}
        \\fn checkTwo(ctx: *RuleContext, node: usize) !void {
        \\    if (node == 0) return;
        \\    const loc_line = node;
        \\    const loc_col = node + 1;
        \\    _ = ctx;
        \\    _ = loc_line;
        \\    _ = loc_col;
        \\    try emitDiag("two");
        \\}
        \\fn emitDiag(_: []const u8) !void {}
    ;

    const result = try runRuleOnSource(allocator, source);
    defer result.diags.deinit();
    try std.testing.expectEqual(@as(usize, 0), result.summary.warnings);
    try std.testing.expectEqual(@as(usize, 1), result.summary.helps);
}

const RunResult = struct {
    diags: @import("../diagnostic.zig").DiagnosticCollection,
    summary: @import("../diagnostic.zig").Summary,
};

fn runRuleOnSource(allocator: std.mem.Allocator, source: []const u8) !RunResult {
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

    var ignores = IgnoreDirectives.init(allocator);
    defer ignores.deinit();

    var diags = DiagnosticCollection.init(allocator);
    defer diags.deinit();

    const config = Config{
        .rules = .{
            .duplicated_code = .{},
        },
    };

    var ctx = RuleContext{
        .allocator = allocator,
        .file = &file,
        .config = config,
        .ignores = &ignores,
        .diagnostics = &diags,
    };

    try run(&ctx);
    return .{ .summary = diags.getSummary(), .diags = diags };
}
