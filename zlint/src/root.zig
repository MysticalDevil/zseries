const std = @import("std");

// Re-export modules
pub const cli = @import("cli.zig");
pub const config = @import("config.zig");
pub const diagnostic = @import("diagnostic.zig");
pub const source_file = @import("source_file.zig");
pub const ignore_directives = @import("ignore_directives.zig");
pub const compile_check = @import("compile_check.zig");
pub const fs_walk = @import("fs_walk.zig");
pub const rules = @import("rules/root.zig");

// Tests
const gpa = std.testing.allocator;

test "basic diagnostic collection" {
    var collection = diagnostic.DiagnosticCollection.init(gpa);
    defer collection.deinit();

    try collection.add(.{
        .rule_id = "test-rule",
        .severity = .err,
        .path = "test.zig",
        .line = 1,
        .column = 1,
        .message = "Test message",
    });

    const summary = collection.getSummary();
    try std.testing.expectEqual(@as(usize, 1), summary.diagnostics);
    try std.testing.expectEqual(@as(usize, 1), summary.errors);
}

test "ignore directives parsing" {
    const source =
        \\// zlint:file-ignore test-rule
        \\const x = 1; // zlint:ignore other-rule
    ;

    var ignores = try ignore_directives.IgnoreDirectives.parse(gpa, source);
    defer ignores.deinit();

    try std.testing.expect(ignores.shouldSuppress("test-rule", 1));
    try std.testing.expect(ignores.shouldSuppress("test-rule", 2)); // file-ignore applies to entire file
    try std.testing.expect(ignores.shouldSuppress("other-rule", 2));
}
