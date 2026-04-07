const std = @import("std");
const SourceFile = @import("../source_file.zig").SourceFile;
const Diagnostic = @import("../diagnostic.zig").Diagnostic;
const Severity = @import("../diagnostic.zig").Severity;
const IgnoreDirectives = @import("../ignore_directives.zig").IgnoreDirectives;
const Config = @import("../config.zig").Config;

/// Rule ID mapping: internal name -> ZAI code
const rule_id_map = std.StaticStringMap([]const u8).initComptime(.{
    .{ "discarded-result", "ZAI001" },
    .{ "max-anytype-params", "ZAI002" },
    .{ "no-empty-catch", "ZAI003" },
    .{ "catch-unreachable", "ZAI004" },
    .{ "defer-return-invalid", "ZAI005" },
    .{ "unused-allocator", "ZAI006" },
    .{ "global-allocator-in-lib", "ZAI007" },
    .{ "no-do-not-optimize-away", "ZAI008" },
    .{ "duplicated-code", "ZAI011" },
});

pub const RuleContext = struct {
    allocator: std.mem.Allocator,
    file: *const SourceFile,
    config: Config,
    ignores: *const IgnoreDirectives,
    diagnostics: *std.ArrayList(Diagnostic),

    pub fn addDiagnostic(self: *RuleContext, rule_id: []const u8, severity: Severity, line: usize, column: usize, message: []const u8) !void {
        // Map internal rule name to ZAI code
        const zai_code = rule_id_map.get(rule_id) orelse rule_id;

        // Check if suppressed (check both ZAI code and internal name)
        if (self.ignores.shouldSuppress(zai_code, line)) return;
        if (self.ignores.shouldSuppress(rule_id, line)) return;

        // Copy the message to ensure it lives as long as the diagnostic
        const msg_copy = try self.allocator.dupe(u8, message);

        try self.diagnostics.append(self.allocator, .{
            .rule_id = zai_code,
            .severity = severity,
            .path = self.file.path,
            .line = line,
            .column = column,
            .message = msg_copy,
        });
    }

    /// Check if we should skip this file (test/example file and config says to skip)
    pub fn shouldSkipFile(self: *RuleContext) bool {
        if (!self.config.scan.skip_tests) return false;
        return self.file.shouldSkipFile();
    }

    /// Check if we should skip this node (inside test block and config says to skip)
    pub fn shouldSkipNode(self: *RuleContext, node: std.zig.Ast.Node.Index) bool {
        if (!self.config.scan.skip_tests) return false;
        return self.file.isInsideTestBlock(node);
    }
};

/// Rule interface
pub const Rule = struct {
    name: []const u8,
    run: *const fn (*RuleContext) anyerror!void,
};

/// Get enabled rules based on configuration
pub fn getEnabledRules(config: Config, allocator: std.mem.Allocator) ![]Rule {
    var rules = std.ArrayList(Rule).empty;

    // Add discarded-result rule if enabled
    if (config.rules.discarded_result) |rule_config| {
        if (rule_config.enabled) {
            try rules.append(allocator, .{
                .name = "discarded-result",
                .run = @import("discarded_result.zig").run,
            });
        }
    } else {
        // Default: enabled
        try rules.append(allocator, .{
            .name = "discarded-result",
            .run = @import("discarded_result.zig").run,
        });
    }

    // Add max-anytype-params rule if enabled
    if (config.rules.max_anytype_params) |rule_config| {
        if (rule_config.enabled) {
            try rules.append(allocator, .{
                .name = "max-anytype-params",
                .run = @import("max_anytype_params.zig").run,
            });
        }
    } else {
        // Default: enabled
        try rules.append(allocator, .{
            .name = "max-anytype-params",
            .run = @import("max_anytype_params.zig").run,
        });
    }

    // Add no-do-not-optimize-away rule if enabled
    if (config.rules.no_do_not_optimize_away) |rule_config| {
        if (rule_config.enabled) {
            try rules.append(allocator, .{
                .name = "no-do-not-optimize-away",
                .run = @import("no_do_not_optimize_away.zig").run,
            });
        }
    } else {
        // Default: enabled
        try rules.append(allocator, .{
            .name = "no-do-not-optimize-away",
            .run = @import("no_do_not_optimize_away.zig").run,
        });
    }

    // Add no-empty-catch rule if enabled
    if (config.rules.no_empty_catch) |rule_config| {
        if (rule_config.enabled) {
            try rules.append(allocator, .{
                .name = "no-empty-catch",
                .run = @import("no_empty_catch.zig").run,
            });
        }
    } else {
        // Default: enabled
        try rules.append(allocator, .{
            .name = "no-empty-catch",
            .run = @import("no_empty_catch.zig").run,
        });
    }

    // Add catch-unreachable rule if enabled
    if (config.rules.catch_unreachable) |rule_config| {
        if (rule_config.enabled) {
            try rules.append(allocator, .{
                .name = "catch-unreachable",
                .run = @import("catch_unreachable.zig").run,
            });
        }
    } else {
        // Default: enabled
        try rules.append(allocator, .{
            .name = "catch-unreachable",
            .run = @import("catch_unreachable.zig").run,
        });
    }

    // Add defer-return-invalid rule if enabled
    if (config.rules.defer_return_invalid) |rule_config| {
        if (rule_config.enabled) {
            try rules.append(allocator, .{
                .name = "defer-return-invalid",
                .run = @import("defer_return_invalid.zig").run,
            });
        }
    } else {
        // Default: enabled
        try rules.append(allocator, .{
            .name = "defer-return-invalid",
            .run = @import("defer_return_invalid.zig").run,
        });
    }

    // Add unused-allocator rule if enabled
    if (config.rules.unused_allocator) |rule_config| {
        if (rule_config.enabled) {
            try rules.append(allocator, .{
                .name = "unused-allocator",
                .run = @import("unused_allocator.zig").run,
            });
        }
    } else {
        // Default: enabled
        try rules.append(allocator, .{
            .name = "unused-allocator",
            .run = @import("unused_allocator.zig").run,
        });
    }

    // Add global-allocator-in-lib rule if enabled
    if (config.rules.global_allocator_in_lib) |rule_config| {
        if (rule_config.enabled) {
            try rules.append(allocator, .{
                .name = "global-allocator-in-lib",
                .run = @import("global_allocator_in_lib.zig").run,
            });
        }
    } else {
        // Default: enabled
        try rules.append(allocator, .{
            .name = "global-allocator-in-lib",
            .run = @import("global_allocator_in_lib.zig").run,
        });
    }

    // Add duplicated-code rule if enabled
    if (config.rules.duplicated_code) |rule_config| {
        if (rule_config.enabled) {
            try rules.append(allocator, .{
                .name = "duplicated-code",
                .run = @import("duplicated_code.zig").run,
            });
        }
    } else {
        // Default: enabled
        try rules.append(allocator, .{
            .name = "duplicated-code",
            .run = @import("duplicated_code.zig").run,
        });
    }

    return rules.toOwnedSlice(allocator);
}
