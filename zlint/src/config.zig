const std = @import("std");

/// Configuration for zlint
pub const Config = struct {
    version: u32 = 1,
    scan: ScanConfig = .{},
    output: OutputConfig = .{},
    rules: RuleConfigs = .{},

    pub const ScanConfig = struct {
        include: []const []const u8 = &.{"."},
        exclude: []const []const u8 = &.{ ".git", "zig-cache", ".zig-cache", "zig-out" },
        skip_tests: bool = true,
    };

    pub const OutputConfig = struct {
        format: []const u8 = "text",
    };

    /// Base configuration for all rules
    pub const BaseRuleConfig = struct {
        enabled: bool = true,
        severity: []const u8 = "error",
    };

    pub const RuleConfigs = struct {
        discarded_result: ?DiscardedResultConfig = null,
        max_anytype_params: ?MaxAnytypeParamsConfig = null,
        no_empty_catch: ?NoEmptyCatchConfig = null,
        no_do_not_optimize_away: ?NoDoNotOptimizeAwayConfig = null,
        catch_unreachable: ?CatchUnreachableConfig = null,
        defer_return_invalid: ?DeferReturnInvalidConfig = null,
        unused_allocator: ?UnusedAllocatorConfig = null,
        global_allocator_in_lib: ?GlobalAllocatorInLibConfig = null,
        duplicated_code: ?DuplicatedCodeConfig = null,
    };

    pub const DiscardedResultConfig = struct {
        base: BaseRuleConfig = .{ .severity = "error" },
        strict: bool = true,
        allow_paths: []const []const u8 = &.{},
        allow_names: []const []const u8 = &.{ "deinit", "free" },
    };

    pub const MaxAnytypeParamsConfig = struct {
        base: BaseRuleConfig = .{},
        max: usize = 2,
    };

    pub const NoDoNotOptimizeAwayConfig = struct {
        base: BaseRuleConfig = .{},
    };

    pub const NoEmptyCatchConfig = struct {
        base: BaseRuleConfig = .{ .severity = "warning" },
    };

    pub const CatchUnreachableConfig = struct {
        base: BaseRuleConfig = .{},
    };

    pub const DeferReturnInvalidConfig = struct {
        base: BaseRuleConfig = .{},
    };

    pub const UnusedAllocatorConfig = struct {
        base: BaseRuleConfig = .{},
    };

    pub const GlobalAllocatorInLibConfig = struct {
        base: BaseRuleConfig = .{},
    };

    pub const DuplicatedCodeConfig = struct {
        base: BaseRuleConfig = .{ .severity = "warning" },
        min_lines: usize = 5,
        min_statements: usize = 3,
    };
};

/// Load configuration from file (simplified for MVP - returns default)
pub fn loadConfig(_: std.mem.Allocator, _: []const u8) !Config {
    // For MVP, return default config
    // TODO: Implement TOML parsing with proper file I/O
    return Config{};
}
