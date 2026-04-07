const std = @import("std");
const zlint = @import("zlint");

// ========================================
// P1 Tests: Code Block Extraction
// ========================================

test "extract function bodies from AST" {
    const allocator = std.testing.allocator;

    const source =
        "const std = @import(\"std\");\\n" ++
        "\\n" ++
        "pub fn foo() void {\\n" ++
        "    const x = 1;\\n" ++
        "    const y = 2;\\n" ++
        "    _ = x + y;\\n" ++
        "}\\n" ++
        "\\n" ++
        "pub fn bar() void {\\n" ++
        "    const a = 1;\\n" ++
        "    const b = 2;\\n" ++
        "    _ = a + b;\\n" ++
        "}\\n";

    var blocks = try zlint.extractBlocks(allocator, source);
    defer blocks.deinit();

    // Should find 2 function bodies
    try std.testing.expectEqual(@as(usize, 2), blocks.items.len);
}

test "extract if statement bodies" {
    const allocator = std.testing.allocator;

    const source =
        "pub fn testIf() void {\\n" ++
        "    if (true) {\\n" ++
        "        const x = 1;\\n" ++
        "        const y = 2;\\n" ++
        "    } else {\\n" ++
        "        const a = 3;\\n" ++
        "        const b = 4;\\n" ++
        "    }\\n" ++
        "}\\n";

    var blocks = try zlint.extractBlocks(allocator, source);
    defer blocks.deinit();

    // Should find: function body, if body, else body = 3 blocks
    try std.testing.expectEqual(@as(usize, 3), blocks.items.len);
}

// ========================================
// P2 Tests: AST Normalization
// ========================================

test "normalize variable names to placeholders" {
    const allocator = std.testing.allocator;

    const source = "const user_id = 123;";
    const normalized = try zlint.normalizeCode(allocator, source);
    defer allocator.free(normalized);

    // Should replace 'user_id' with $VAR0
    try std.testing.expect(std.mem.indexOf(u8, normalized, "$VAR0") != null);
    try std.testing.expect(std.mem.indexOf(u8, normalized, "user_id") == null);
}

test "normalize preserves structure" {
    const allocator = std.testing.allocator;

    const source1 = "const x = a + b;";
    const source2 = "const y = c + d;";

    const norm1 = try zlint.normalizeCode(allocator, source1);
    defer allocator.free(norm1);
    const norm2 = try zlint.normalizeCode(allocator, source2);
    defer allocator.free(norm2);

    // After normalization, both should have same structure
    try std.testing.expectEqualStrings(norm1, norm2);
}

// ========================================
// P3 Tests: Duplicate Detection
// ========================================

test "detect exact 5-line duplicate" {
    const allocator = std.testing.allocator;

    const source =
        "pub fn foo() void {\\n" ++
        "    const a = 1;\\n" ++
        "    const b = 2;\\n" ++
        "    const c = 3;\\n" ++
        "    const d = 4;\\n" ++
        "    const e = 5;\\n" ++
        "}\\n" ++
        "\\n" ++
        "pub fn bar() void {\\n" ++
        "    const a = 1;\\n" ++
        "    const b = 2;\\n" ++
        "    const c = 3;\\n" ++
        "    const d = 4;\\n" ++
        "    const e = 5;\\n" ++
        "}\\n";

    var dups = try zlint.findDuplicates(allocator, source, .{ .min_lines = 5 });
    defer dups.deinit();

    // Should find 1 duplicate pair
    try std.testing.expectEqual(@as(usize, 1), dups.items.len);
}

test "detect duplicate with different variable names" {
    const allocator = std.testing.allocator;

    const source =
        "pub fn foo() void {\\n" ++
        "    const user_id = 1;\\n" ++
        "    const user_name = \"test\";\\n" ++
        "    save(user_id, user_name);\\n" ++
        "}\\n" ++
        "\\n" ++
        "pub fn bar() void {\\n" ++
        "    const order_id = 1;\\n" ++
        "    const order_name = \"test\";\\n" ++
        "    save(order_id, order_name);\\n" ++
        "}\\n";

    var dups = try zlint.findDuplicates(allocator, source, .{ .min_lines = 3 });
    defer dups.deinit();

    // Should detect as duplicate (structure same, variables renamed)
    try std.testing.expect(dups.items.len > 0);
}

test "do not detect 4-line as duplicate when threshold is 5" {
    const allocator = std.testing.allocator;

    const source =
        "pub fn foo() void {\\n" ++
        "    const a = 1;\\n" ++
        "    const b = 2;\\n" ++
        "    const c = 3;\\n" ++
        "    const d = 4;\\n" ++
        "}\\n" ++
        "\\n" ++
        "pub fn bar() void {\\n" ++
        "    const a = 1;\\n" ++
        "    const b = 2;\\n" ++
        "    const c = 3;\\n" ++
        "    const d = 4;\\n" ++
        "}\\n";

    var dups = try zlint.findDuplicates(allocator, source, .{ .min_lines = 5 });
    defer dups.deinit();

    // Should NOT find duplicates (only 4 lines, threshold is 5)
    try std.testing.expectEqual(@as(usize, 0), dups.items.len);
}

// ========================================
// P4 Tests: Branch Duplication
// ========================================

test "detect duplicate if/else branches" {
    const allocator = std.testing.allocator;

    const source =
        "pub fn test() void {\\n" ++
        "    if (cond) {\\n" ++
        "        const x = 1;\\n" ++
        "        const y = 2;\\n" ++
        "        process(x, y);\\n" ++
        "    } else {\\n" ++
        "        const a = 1;\\n" ++
        "        const b = 2;\\n" ++
        "        process(a, b);\\n" ++
        "    }\\n" ++
        "}\\n";

    var dups = try zlint.findBranchDuplicates(allocator, source);
    defer dups.deinit();

    // Should detect if and else bodies are duplicates
    try std.testing.expect(dups.items.len > 0);
}

test "exclude switch case bodies from duplicate detection" {
    const allocator = std.testing.allocator;

    const source =
        "pub fn test() void {\\n" ++
        "    switch (val) {\\n" ++
        "        .A => {\\n" ++
        "            const x = 1;\\n" ++
        "            const y = 2;\\n" ++
        "        },\\n" ++
        "        .B => {\\n" ++
        "            const a = 1;\\n" ++
        "            const b = 2;\\n" ++
        "        },\\n" ++
        "    }\\n" ++
        "}\\n";

    var dups = try zlint.findDuplicates(allocator, source, .{});
    defer dups.deinit();

    // Switch case bodies should be excluded
    try std.testing.expectEqual(@as(usize, 0), dups.items.len);
}

// ========================================
// P5 Tests: Exclusions
// ========================================

test "exclude error handling boilerplate" {
    const allocator = std.testing.allocator;

    const source =
        "pub fn test() void {\\n" ++
        "    try foo() catch |err| switch (err) {\\n" ++
        "        error.A => handleA(),\\n" ++
        "        error.B => handleB(),\\n" ++
        "        error.C => handleC(),\\n" ++
        "    };\\n" ++
        "}\\n";

    var dups = try zlint.findDuplicates(allocator, source, .{ .exclude_error_handling = true });
    defer dups.deinit();

    // Error handling should be excluded
    try std.testing.expectEqual(@as(usize, 0), dups.items.len);
}

test "exclude generated code with comment marker" {
    const allocator = std.testing.allocator;

    const source =
        "// zlint: ignore-generated\\n" ++
        "pub fn foo() void {\\n" ++
        "    const a = 1;\\n" ++
        "    const b = 2;\\n" ++
        "}\\n" ++
        "\\n" ++
        "// zlint: ignore-generated\\n" ++
        "pub fn bar() void {\\n" ++
        "    const a = 1;\\n" ++
        "    const b = 2;\\n" ++
        "}\\n";

    var dups = try zlint.findDuplicates(allocator, source, .{});
    defer dups.deinit();

    // Generated code should be excluded
    try std.testing.expectEqual(@as(usize, 0), dups.items.len);
}
