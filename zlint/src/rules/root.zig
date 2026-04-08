const std = @import("std");
const SourceFile = @import("../source_file.zig").SourceFile;
const DiagnosticCollection = @import("../diagnostic.zig").DiagnosticCollection;
const Severity = @import("../diagnostic.zig").Severity;
const IgnoreDirectives = @import("../ignore_directives.zig").IgnoreDirectives;
const Config = @import("../config.zig").Config;
const rule_ids = @import("../rule_ids.zig");

// Import all rule modules
const discarded_result = @import("discarded_result.zig");
const max_anytype_params = @import("max_anytype_params.zig");
const no_empty_block = @import("no_empty_block.zig");
const catch_unreachable = @import("catch_unreachable.zig");
const defer_return_invalid = @import("defer_return_invalid.zig");
const unused_allocator = @import("unused_allocator.zig");
const global_allocator_in_lib = @import("global_allocator_in_lib.zig");
const no_do_not_optimize_away = @import("no_do_not_optimize_away.zig");
const duplicated_code = @import("duplicated_code.zig");
const discard_assignment = @import("discard_assignment.zig");
const no_anytype_io_params = @import("no_anytype_io_params.zig");

// Public utilities for rule authors
pub const utils = @import("utils.zig");

pub const RuleContext = struct {
    allocator: std.mem.Allocator,
    file: *const SourceFile,
    config: Config,
    ignores: *const IgnoreDirectives,
    diagnostics: *DiagnosticCollection,

    pub fn addDiagnostic(self: *RuleContext, rule_id: []const u8, severity: Severity, line: usize, column: usize, message: []const u8) !void {
        if (self.ignores.shouldSuppress(rule_id, line)) return;

        try self.diagnostics.add(.{
            .rule_id = rule_id,
            .severity = severity,
            .path = self.file.path,
            .line = line,
            .column = column,
            .message = message,
        });
    }

    pub fn shouldSkipFile(self: *RuleContext) bool {
        if (!self.config.scan.skip_tests) return false;
        return self.file.shouldSkipFile();
    }

    pub fn shouldSkipNode(self: *RuleContext, node: std.zig.Ast.Node.Index) bool {
        if (!self.config.scan.skip_tests) return false;
        return self.file.isInsideTestBlock(node);
    }
};

/// Rule interface
pub const Rule = struct {
    id: []const u8,
    name: []const u8,
    run: *const fn (*RuleContext) anyerror!void,
};

/// Rule definition entry
const RuleEntry = struct {
    id: []const u8,
    name: []const u8,
    run: *const fn (*RuleContext) anyerror!void,
};

/// All available rules - table-driven registration
const ALL_RULES: []const RuleEntry = &.{
    .{ .id = rule_ids.discarded_result, .name = "discarded_result", .run = discarded_result.run },
    .{ .id = rule_ids.max_anytype_params, .name = "max_anytype_params", .run = max_anytype_params.run },
    .{ .id = rule_ids.no_empty_block, .name = "no_empty_block", .run = no_empty_block.run },
    .{ .id = rule_ids.discard_assignment, .name = "discard_assignment", .run = discard_assignment.run },
    .{ .id = rule_ids.catch_unreachable, .name = "catch_unreachable", .run = catch_unreachable.run },
    .{ .id = rule_ids.defer_return_invalid, .name = "defer_return_invalid", .run = defer_return_invalid.run },
    .{ .id = rule_ids.unused_allocator, .name = "unused_allocator", .run = unused_allocator.run },
    .{ .id = rule_ids.global_allocator_in_lib, .name = "global_allocator_in_lib", .run = global_allocator_in_lib.run },
    .{ .id = rule_ids.no_do_not_optimize_away, .name = "no_do_not_optimize_away", .run = no_do_not_optimize_away.run },
    .{ .id = rule_ids.duplicated_code, .name = "duplicated_code", .run = duplicated_code.run },
    .{ .id = rule_ids.no_anytype_io_params, .name = "no_anytype_io_params", .run = no_anytype_io_params.run },
};

/// Rules enabled by default - explicit list
const DEFAULT_ENABLED_RULES: []const []const u8 = &.{
    "discarded_result",
    "max_anytype_params",
    "no_empty_block",
    "catch_unreachable",
    "defer_return_invalid",
    "unused_allocator",
    "global_allocator_in_lib",
    "no_do_not_optimize_away",
    "duplicated_code",
    "no_anytype_io_params",
};

/// Check if rule is in default enabled list
fn isDefaultEnabled(name: []const u8) bool {
    for (DEFAULT_ENABLED_RULES) |enabled| {
        if (std.mem.eql(u8, enabled, name)) return true;
    }
    return false;
}

/// Check if rule is enabled using comptime field access
fn isRuleEnabled(comptime entry: RuleEntry, config: Config) bool {
    // Check if config has explicit override
    const optional_config = @field(config.rules, entry.name);
    if (optional_config) |cfg| {
        return cfg.base.enabled;
    }

    // Fall back to default list
    return isDefaultEnabled(entry.name);
}

pub fn isKnownRuleId(rule_id: []const u8) bool {
    for (ALL_RULES) |entry| {
        if (std.mem.eql(u8, entry.id, rule_id)) return true;
    }
    return false;
}

/// Get all enabled rules
pub fn getEnabledRules(config: Config, allocator: std.mem.Allocator) ![]Rule {
    var rules = std.ArrayList(Rule).empty;

    inline for (ALL_RULES) |entry| {
        if (isRuleEnabled(entry, config)) {
            try rules.append(allocator, .{
                .id = entry.id,
                .name = entry.name,
                .run = entry.run,
            });
        }
    }

    return rules.toOwnedSlice(allocator);
}
