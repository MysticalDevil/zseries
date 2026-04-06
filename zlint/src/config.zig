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

    pub const RuleConfigs = struct {
        discarded_result: ?DiscardedResultConfig = null,
        max_anytype_params: ?MaxAnytypeParamsConfig = null,
        no_do_not_optimize_away: ?NoDoNotOptimizeAwayConfig = null,
        no_empty_catch: ?NoEmptyCatchConfig = null,
        ZAI004: ?ZAI004Config = null,
        ZAI005: ?ZAI005Config = null,
        ZAI006: ?ZAI006Config = null,
        ZAI007: ?ZAI007Config = null,
    };

    pub const DiscardedResultConfig = struct {
        enabled: bool = true,
        severity: []const u8 = "error",
        strict: bool = true,
        allow_paths: []const []const u8 = &.{},
        allow_names: []const []const u8 = &.{ "deinit", "free" },
    };

    pub const MaxAnytypeParamsConfig = struct {
        enabled: bool = true,
        severity: []const u8 = "error",
        max: usize = 2,
    };

    pub const NoDoNotOptimizeAwayConfig = struct {
        enabled: bool = true,
        severity: []const u8 = "error",
    };

    pub const NoEmptyCatchConfig = struct {
        enabled: bool = true,
        severity: []const u8 = "warning",
    };

    pub const ZAI004Config = struct {
        enabled: bool = true,
        severity: []const u8 = "error",
    };

    pub const ZAI005Config = struct {
        enabled: bool = true,
        severity: []const u8 = "error",
    };

    pub const ZAI006Config = struct {
        enabled: bool = true,
        severity: []const u8 = "error",
    };

    pub const ZAI007Config = struct {
        enabled: bool = true,
        severity: []const u8 = "error",
    };
};

/// Load configuration from file (simplified for MVP - returns default)
pub fn loadConfig(_: std.mem.Allocator, _: []const u8) !Config {
    // For MVP, return default config
    // TODO: Implement TOML parsing with proper file I/O
    return Config{};
}
