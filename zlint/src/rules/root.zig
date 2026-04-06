const std = @import("std");
const SourceFile = @import("../source_file.zig").SourceFile;
const Diagnostic = @import("../diagnostic.zig").Diagnostic;
const Severity = @import("../diagnostic.zig").Severity;
const IgnoreDirectives = @import("../ignore_directives.zig").IgnoreDirectives;
const Config = @import("../config.zig").Config;

pub const RuleContext = struct {
    allocator: std.mem.Allocator,
    file: *const SourceFile,
    config: Config,
    ignores: *const IgnoreDirectives,
    diagnostics: *std.ArrayList(Diagnostic),

    pub fn addDiagnostic(self: *RuleContext, rule_id: []const u8, severity: Severity, line: usize, column: usize, message: []const u8) !void {
        // Check if suppressed
        if (self.ignores.shouldSuppress(rule_id, line)) return;

        try self.diagnostics.append(self.allocator, .{
            .rule_id = rule_id,
            .severity = severity,
            .path = self.file.path,
            .line = line,
            .column = column,
            .message = message,
        });
    }
};

/// Rule interface
pub const Rule = struct {
    name: []const u8,
    run: *const fn (*RuleContext) anyerror!void,
};

/// Get all enabled rules
pub fn getEnabledRules(config: Config, allocator: std.mem.Allocator) ![]Rule {
    var rules = std.ArrayList(Rule).empty;
    errdefer rules.deinit(allocator);

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

    return rules.toOwnedSlice(allocator);
}
