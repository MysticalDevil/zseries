const std = @import("std");

// Re-export modules
pub const cli = @import("cli.zig");
pub const config = @import("config.zig");
pub const diagnostic = @import("diagnostic.zig");
pub const rule_ids = @import("rule_ids.zig");
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
        .rule_id = "discarded_result",
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
        \\// zlint:file-ignore discarded_result
        \\const x = 1; // zlint:ignore no_empty_block
    ;

    var ignores = try ignore_directives.IgnoreDirectives.parse(gpa, source);
    defer ignores.deinit();

    try std.testing.expect(ignores.shouldSuppress("discarded_result", 1));
    try std.testing.expect(ignores.shouldSuppress("discarded_result", 2));
    try std.testing.expect(ignores.shouldSuppress("no_empty_block", 2));
}
