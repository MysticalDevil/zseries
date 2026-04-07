const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const Severity = @import("../diagnostic.zig").Severity;
const locations = @import("../ast/locations.zig");

// P1: Code Block Extraction
pub const CodeBlock = struct {
    node: std.zig.Ast.Node.Index,
    start_line: usize,
    end_line: usize,
};

pub const BlockList = struct {
    allocator: std.mem.Allocator,
    items: []CodeBlock,

    pub fn deinit(self: *BlockList) void {
        self.allocator.free(self.items);
    }
};

pub fn extractBlocks(allocator: std.mem.Allocator, source: [:0]const u8) !BlockList {
    var ast = try std.zig.Ast.parse(allocator, source, .zig);
    defer ast.deinit(allocator);

    var blocks = std.ArrayList(CodeBlock).empty;
    defer blocks.deinit(allocator);

    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);

        switch (tag) {
            .fn_decl => {
                const body = ast.nodeData(node).node_and_node[1];
                if (@intFromEnum(body) != 0) {
                    const start_loc = locations.getNodeLocation(ast, body, source);
                    const end_loc = locations.getTokenLocation(ast, ast.lastToken(body), source);
                    try blocks.append(allocator, .{
                        .node = body,
                        .start_line = start_loc.line,
                        .end_line = end_loc.line,
                    });
                }
            },
            else => {},
        }
    }

    return BlockList{
        .allocator = allocator,
        .items = try blocks.toOwnedSlice(allocator),
    };
}

// P2: AST Normalization
pub fn normalizeCode(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).empty;
    defer result.deinit(allocator);

    var i: usize = 0;
    var var_counter: usize = 0;

    var var_map = std.StringHashMap(usize).init(allocator);
    defer var_map.deinit();

    while (i < source.len) {
        if (std.ascii.isWhitespace(source[i])) {
            try result.append(allocator, source[i]);
            i += 1;
            continue;
        }

        if (isIdentStart(source[i])) {
            const start = i;
            while (i < source.len and isIdentChar(source[i])) {
                i += 1;
            }
            const ident = source[start..i];

            const entry = try var_map.getOrPut(ident);
            if (!entry.found_existing) {
                entry.value_ptr.* = var_counter;
                var_counter += 1;
            }

            try result.append(allocator, '$');
            try result.append(allocator, 'V');
            try result.append(allocator, 'A');
            try result.append(allocator, 'R');

            var buf: [32]u8 = undefined;
            const num_str = try std.fmt.bufPrint(&buf, "{d}", .{entry.value_ptr.*});
            for (num_str) |c| {
                try result.append(allocator, c);
            }
        } else {
            try result.append(allocator, source[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

fn isIdentStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isIdentChar(c: u8) bool {
    return isIdentStart(c) or (c >= '0' and c <= '9');
}

// P3: Duplicate Detection
pub const Duplicate = struct {
    start_line_1: usize,
    start_line_2: usize,
    length: usize,
    similarity: f32,
};

pub const DuplicateList = struct {
    allocator: std.mem.Allocator,
    items: []Duplicate,

    pub fn deinit(self: *DuplicateList) void {
        self.allocator.free(self.items);
    }
};

pub const DetectionOptions = struct {
    min_lines: usize = 5,
    min_statements: usize = 3,
    exclude_error_handling: bool = true,
};

pub fn findDuplicates(
    allocator: std.mem.Allocator,
    source: [:0]const u8,
    options: DetectionOptions,
) !DuplicateList {
    var dups = std.ArrayList(Duplicate).empty;
    defer dups.deinit(allocator);

    const normalized = try normalizeCode(allocator, source);
    defer allocator.free(normalized);

    var lines = std.ArrayList([]const u8).empty;
    defer lines.deinit(allocator);

    var it = std.mem.splitScalar(u8, normalized, '\n');
    while (it.next()) |line| {
        try lines.append(allocator, line);
    }

    const min_lines = options.min_lines;

    var i: usize = 0;
    while (i + min_lines <= lines.items.len) : (i += 1) {
        const window1 = lines.items[i .. i + min_lines];

        var j: usize = i + min_lines;
        while (j + min_lines <= lines.items.len) : (j += 1) {
            const window2 = lines.items[j .. j + min_lines];

            if (areWindowsEqual(window1, window2)) {
                try dups.append(allocator, .{
                    .start_line_1 = i + 1,
                    .start_line_2 = j + 1,
                    .length = min_lines,
                    .similarity = 1.0,
                });
            }
        }
    }

    return DuplicateList{
        .allocator = allocator,
        .items = try dups.toOwnedSlice(allocator),
    };
}

fn areWindowsEqual(window1: [][]const u8, window2: [][]const u8) bool {
    if (window1.len != window2.len) return false;

    for (window1, window2) |line1, line2| {
        if (!std.mem.eql(u8, line1, line2)) return false;
    }

    return true;
}

// P4: Branch Duplication Detection
pub fn findBranchDuplicates(
    allocator: std.mem.Allocator,
    source: [:0]const u8,
) !DuplicateList {
    var dups = std.ArrayList(Duplicate).empty;
    defer dups.deinit(allocator);

    var ast = try std.zig.Ast.parse(allocator, source, .zig);
    defer ast.deinit(allocator);

    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(i);

        // Check if/else branches using fullIf
        if (tag == .@"if") {
            if (ast.fullIf(node)) |if_info| {
                const then_body = if_info.ast.then_expr;
                const else_body = if_info.ast.else_expr;

                if (@intFromEnum(then_body) != 0 and else_body != .none) {
                    try compareBranches(allocator, &ast, source, then_body, else_body.unwrap().?, &dups);
                }
            }
        }
    }

    return DuplicateList{
        .allocator = allocator,
        .items = try dups.toOwnedSlice(allocator),
    };
}

fn compareBranches(
    allocator: std.mem.Allocator,
    ast: *const std.zig.Ast,
    source: [:0]const u8,
    then_body: std.zig.Ast.Node.Index,
    else_body: std.zig.Ast.Node.Index,
    dups: *std.ArrayList(Duplicate),
) !void {
    // Extract source text for both branches
    const then_start = locations.getNodeLocation(ast.*, then_body, source);
    const then_end = locations.getTokenLocation(ast.*, ast.lastToken(then_body), source);
    const else_start = locations.getNodeLocation(ast.*, else_body, source);
    const else_end = locations.getTokenLocation(ast.*, ast.lastToken(else_body), source);

    const then_text = try extractLines(allocator, source, then_start.line, then_end.line);
    defer allocator.free(then_text);

    const else_text = try extractLines(allocator, source, else_start.line, else_end.line);
    defer allocator.free(else_text);

    // Normalize and compare
    const norm_then = try normalizeCode(allocator, then_text);
    defer allocator.free(norm_then);

    const norm_else = try normalizeCode(allocator, else_text);
    defer allocator.free(norm_else);

    // Check if they are identical or very similar
    if (std.mem.eql(u8, norm_then, norm_else)) {
        try dups.append(allocator, .{
            .start_line_1 = then_start.line,
            .start_line_2 = else_start.line,
            .length = @max(1, then_end.line - then_start.line + 1),
            .similarity = 1.0,
        });
    }
}

fn extractLines(allocator: std.mem.Allocator, source: [:0]const u8, start_line: usize, end_line: usize) ![]const u8 {
    var result = std.ArrayList(u8).empty;
    defer result.deinit(allocator);

    var current_line: usize = 1;
    var i: usize = 0;

    while (i < source.len and current_line <= end_line) {
        if (current_line >= start_line) {
            try result.append(allocator, source[i]);
        }

        if (source[i] == '\n') {
            current_line += 1;
        }

        i += 1;
    }

    return result.toOwnedSlice(allocator);
}

// P5: Main Rule Entry Point
pub fn run(ctx: *RuleContext) !void {
    const source = ctx.file.content;
    const allocator = ctx.allocator;

    // Skip if file should be skipped
    if (ctx.shouldSkipFile()) return;

    // Track allocated messages to free later
    var messages = std.ArrayList([]const u8).empty;
    defer {
        for (messages.items) |msg| {
            allocator.free(msg);
        }
        messages.deinit(allocator);
    }

    // Find duplicates with increased threshold to reduce false positives
    const options = DetectionOptions{
        .min_lines = 8,
        .min_statements = 3,
        .exclude_error_handling = true,
    };

    var dups = try findDuplicates(allocator, source, options);
    defer dups.deinit();

    for (dups.items) |dup| {
        const message = try std.fmt.allocPrint(allocator, "Found {d} lines of duplicated code (similarity: {d:.0}%) starting at lines {d} and {d}", .{
            dup.length,
            dup.similarity * 100.0,
            dup.start_line_1,
            dup.start_line_2,
        });
        try messages.append(allocator, message);

        try ctx.addDiagnostic(
            "duplicated-code",
            .warning,
            dup.start_line_1,
            1,
            message,
        );
    }

    // Find branch duplicates
    var branch_dups = try findBranchDuplicates(allocator, source);
    defer branch_dups.deinit();

    for (branch_dups.items) |dup| {
        const message = try std.fmt.allocPrint(allocator, "if/else branches contain duplicated code at lines {d} and {d}", .{
            dup.start_line_1,
            dup.start_line_2,
        });
        try messages.append(allocator, message);

        try ctx.addDiagnostic(
            "duplicated-code",
            .warning,
            dup.start_line_1,
            1,
            message,
        );
    }
}

// ========================================
// Tests
// ========================================

test "extractBlocks returns empty list for empty source" {
    const allocator = std.testing.allocator;

    var blocks = try extractBlocks(allocator, "");
    defer blocks.deinit();

    try std.testing.expectEqual(@as(usize, 0), blocks.items.len);
}

test "extractBlocks finds single function body" {
    const allocator = std.testing.allocator;

    const source = "pub fn foo() void { const x = 1; }";
    var blocks = try extractBlocks(allocator, source);
    defer blocks.deinit();

    try std.testing.expectEqual(@as(usize, 1), blocks.items.len);
}

test "extractBlocks finds two function bodies" {
    const allocator = std.testing.allocator;

    const source =
        "pub fn foo() void { const x = 1; }" ++
        "pub fn bar() void { const y = 2; }";

    var blocks = try extractBlocks(allocator, source);
    defer blocks.deinit();

    try std.testing.expectEqual(@as(usize, 2), blocks.items.len);
}

test "normalizeCode replaces identifiers with placeholders" {
    const allocator = std.testing.allocator;

    const source = "const user_id = 123;";
    const normalized = try normalizeCode(allocator, source);
    defer allocator.free(normalized);

    try std.testing.expect(std.mem.indexOf(u8, normalized, "$VAR") != null);
    try std.testing.expect(std.mem.indexOf(u8, normalized, "user_id") == null);
}

test "normalizeCode produces same output for structurally similar code" {
    const allocator = std.testing.allocator;

    const source1 = "const a = x + y;";
    const source2 = "const b = m + n;";

    const norm1 = try normalizeCode(allocator, source1);
    defer allocator.free(norm1);
    const norm2 = try normalizeCode(allocator, source2);
    defer allocator.free(norm2);

    try std.testing.expectEqualStrings(norm1, norm2);
}

test "findDuplicates returns empty list for different code" {
    const allocator = std.testing.allocator;

    const source = "pub fn foo() {} pub fn bar() {}";
    var dups = try findDuplicates(allocator, source, .{});
    defer dups.deinit();

    try std.testing.expectEqual(@as(usize, 0), dups.items.len);
}

test "findDuplicates detects exact 5-line duplicate" {
    const allocator = std.testing.allocator;

    const source =
        "pub fn foo() void {\n" ++
        "    const a = 1;\n" ++
        "    const b = 2;\n" ++
        "    const c = 3;\n" ++
        "    const d = 4;\n" ++
        "    const e = 5;\n" ++
        "}\n" ++
        "\n" ++
        "pub fn bar() void {\n" ++
        "    const a = 1;\n" ++
        "    const b = 2;\n" ++
        "    const c = 3;\n" ++
        "    const d = 4;\n" ++
        "    const e = 5;\n" ++
        "}\n";

    var dups = try findDuplicates(allocator, source, .{ .min_lines = 5 });
    defer dups.deinit();

    try std.testing.expect(dups.items.len > 0);
}

test "findDuplicates detects duplicates with different variable names" {
    const allocator = std.testing.allocator;

    const source =
        "pub fn foo() void {\n" ++
        "    const user_id = 1;\n" ++
        "    const user_name = \"test\";\n" ++
        "    save(user_id, user_name);\n" ++
        "}\n" ++
        "\n" ++
        "pub fn bar() void {\n" ++
        "    const order_id = 1;\n" ++
        "    const order_name = \"test\";\n" ++
        "    save(order_id, order_name);\n" ++
        "}\n";

    var dups = try findDuplicates(allocator, source, .{ .min_lines = 3 });
    defer dups.deinit();

    try std.testing.expect(dups.items.len > 0);
}

test "findDuplicates does not detect 4-line as duplicate when threshold is 5" {
    const allocator = std.testing.allocator;

    const source =
        "pub fn foo() void {\n" ++
        "    const a = 1;\n" ++
        "    const b = 2;\n" ++
        "    const c = 3;\n" ++
        "    const d = 4;\n" ++
        "}\n" ++
        "\n" ++
        "pub fn bar() void {\n" ++
        "    const a = 1;\n" ++
        "    const b = 2;\n" ++
        "    const c = 3;\n" ++
        "    const d = 4;\n" ++
        "}\n";

    var dups = try findDuplicates(allocator, source, .{ .min_lines = 5 });
    defer dups.deinit();

    try std.testing.expectEqual(@as(usize, 0), dups.items.len);
}

test "findBranchDuplicates detects duplicate if/else branches" {
    const allocator = std.testing.allocator;

    const source =
        "pub fn test() void {\n" ++
        "    if (cond) {\n" ++
        "        const x = 1;\n" ++
        "        const y = 2;\n" ++
        "        process(x, y);\n" ++
        "    } else {\n" ++
        "        const a = 1;\n" ++
        "        const b = 2;\n" ++
        "        process(a, b);\n" ++
        "    }\n" ++
        "}\n";

    var dups = try findBranchDuplicates(allocator, source);
    defer dups.deinit();

    try std.testing.expect(dups.items.len > 0);
}
