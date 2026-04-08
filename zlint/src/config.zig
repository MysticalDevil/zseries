const std = @import("std");
const ztoml = @import("ztoml");

/// Configuration for zlint
pub const Config = struct {
    version: u32 = 1,
    strict_config: bool = true,
    strict_exit: bool = false,
    fail_on_warning: bool = false,
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
        no_silent_error_handling: ?NoSilentErrorHandlingConfig = null,
        discard_assignment: ?DiscardAssignmentConfig = null,
        catch_unreachable: ?CatchUnreachableConfig = null,
        orelse_unreachable: ?OrelseUnreachableConfig = null,
        unwrap_optional: ?UnwrapOptionalConfig = null,
        suspicious_cast_chain: ?SuspiciousCastChainConfig = null,
        no_anyerror_return: ?NoAnyerrorReturnConfig = null,
        defer_return_invalid: ?DeferReturnInvalidConfig = null,
        no_do_not_optimize_away: ?NoDoNotOptimizeAwayConfig = null,
        unused_allocator: ?UnusedAllocatorConfig = null,
        global_allocator_in_lib: ?GlobalAllocatorInLibConfig = null,
        duplicated_code: ?DuplicatedCodeConfig = null,
        no_anytype_io_params: ?NoAnytypeIoParamsConfig = null,
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

    pub const NoSilentErrorHandlingConfig = struct {
        base: BaseRuleConfig = .{ .severity = "warning" },
    };

    pub const DiscardAssignmentConfig = struct {
        base: BaseRuleConfig = .{ .severity = "warning", .enabled = false },
    };

    pub const CatchUnreachableConfig = struct {
        base: BaseRuleConfig = .{},
    };

    pub const OrelseUnreachableConfig = struct {
        base: BaseRuleConfig = .{},
    };

    pub const UnwrapOptionalConfig = struct {
        base: BaseRuleConfig = .{ .severity = "warning" },
    };

    pub const SuspiciousCastChainConfig = struct {
        base: BaseRuleConfig = .{ .severity = "warning" },
    };

    pub const NoAnyerrorReturnConfig = struct {
        base: BaseRuleConfig = .{ .severity = "warning" },
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
        min_lines: usize = 8,
        min_statements: usize = 4,
        min_tokens: usize = 40,
        min_similarity_percent: usize = 96,
        min_fuzzy_lines: usize = 20,
        max_reports_per_file: usize = 12,
    };

    pub const NoAnytypeIoParamsConfig = struct {
        base: BaseRuleConfig = .{ .severity = "error" },
        io_param_aliases: []const []const u8 = &.{ "writer", "reader", "out_writer", "in_reader", "w", "r" },
        allow_types: []const []const u8 = &.{},
    };
};

const ConfigError = error{
    InvalidConfig,
};

const ParseError = ConfigError || std.mem.Allocator.Error;

fn configFail(cfg: Config, comptime fmt: []const u8, args: anytype) ConfigError!void {
    if (cfg.strict_config) {
        std.log.err(fmt, args);
        return ConfigError.InvalidConfig;
    }
    std.log.warn(fmt, args);
}

fn parseSeverity(value: []const u8, cfg: Config, context: []const u8) ConfigError![]const u8 {
    if (std.mem.eql(u8, value, "error") or std.mem.eql(u8, value, "warning")) {
        return value;
    }
    try configFail(cfg, "Invalid severity '{s}' for {s}; using default", .{ value, context });
    return "error";
}

fn parseStringArray(allocator: std.mem.Allocator, node: *const ztoml.Value, cfg: Config, context: []const u8) ParseError![]const []const u8 {
    switch (node.*) {
        .Array => |arr| {
            const out = try allocator.alloc([]const u8, arr.items.len);
            for (arr.items, 0..) |item, i| {
                const s = item.getString() orelse {
                    allocator.free(out);
                    try configFail(cfg, "Expected string in array for {s}", .{context});
                    return ConfigError.InvalidConfig;
                };
                out[i] = try allocator.dupe(u8, s);
            }
            return out;
        },
        else => {
            try configFail(cfg, "Expected array for {s}", .{context});
            return ConfigError.InvalidConfig;
        },
    }
}

fn parseBaseRuleConfig(node: *const ztoml.Value, base: *Config.BaseRuleConfig, cfg: Config, context: []const u8) ConfigError!void {
    if (node.get("enabled")) |enabled_node| {
        if (enabled_node.getBoolean()) |v| {
            base.enabled = v;
        } else {
            try configFail(cfg, "{s}.enabled must be boolean", .{context});
        }
    }

    if (node.get("severity")) |severity_node| {
        if (severity_node.getString()) |sev| {
            base.severity = try parseSeverity(sev, cfg, context);
        } else {
            try configFail(cfg, "{s}.severity must be string", .{context});
        }
    }
}

fn ensureKnownKeys(table: std.StringHashMap(ztoml.Value), known: []const []const u8, cfg: Config, context: []const u8) ConfigError!void {
    var it = table.iterator();
    while (it.next()) |entry| {
        var ok = false;
        for (known) |k| {
            if (std.mem.eql(u8, entry.key_ptr.*, k)) {
                ok = true;
                break;
            }
        }
        if (!ok) {
            try configFail(cfg, "Unknown key '{s}' in {s}", .{ entry.key_ptr.*, context });
        }
    }
}

const RuleKey = enum {
    discarded_result,
    max_anytype_params,
    no_silent_error_handling,
    discard_assignment,
    catch_unreachable,
    orelse_unreachable,
    unwrap_optional,
    suspicious_cast_chain,
    no_anyerror_return,
    defer_return_invalid,
    unused_allocator,
    global_allocator_in_lib,
    no_do_not_optimize_away,
    duplicated_code,
    no_anytype_io_params,
};

fn parseBaseOnlyRule(
    comptime field_name: []const u8,
    comptime RuleType: type,
    rules_cfg: *Config.RuleConfigs,
    rule_node: *const ztoml.Value,
    cfg: Config,
    context: []const u8,
) ParseError!void {
    var rc = RuleType{};
    try parseBaseRuleConfig(rule_node, &rc.base, cfg, context);
    @field(rules_cfg, field_name) = rc;
}

fn parsePositiveIntField(
    rule_node: *const ztoml.Value,
    field_name: []const u8,
) ParseError!?usize {
    const n = rule_node.get(field_name) orelse return null;
    const value = n.getInteger() orelse return ConfigError.InvalidConfig;
    if (value < 1) return ConfigError.InvalidConfig;
    return @intCast(value);
}

fn parseRuleEntry(
    allocator: std.mem.Allocator,
    cfg: Config,
    rules_cfg: *Config.RuleConfigs,
    key: []const u8,
    rule_node: *const ztoml.Value,
) ParseError!void {
    const rk = std.meta.stringToEnum(RuleKey, key) orelse {
        try configFail(cfg, "Unknown rule key rules.{s}", .{key});
        return;
    };

    switch (rk) {
        .discarded_result => {
            var rc = Config.DiscardedResultConfig{};
            try parseBaseRuleConfig(rule_node, &rc.base, cfg, "rules.discarded_result");
            if (rule_node.get("strict")) |n| {
                if (n.getBoolean()) |v| {
                    rc.strict = v;
                } else {
                    try configFail(cfg, "rules.discarded_result.strict must be bool", .{});
                }
            }
            if (rule_node.get("allow_names")) |n| rc.allow_names = try parseStringArray(allocator, n, cfg, "rules.discarded_result.allow_names");
            if (rule_node.get("allow_paths")) |n| rc.allow_paths = try parseStringArray(allocator, n, cfg, "rules.discarded_result.allow_paths");
            rules_cfg.discarded_result = rc;
        },
        .max_anytype_params => {
            var rc = Config.MaxAnytypeParamsConfig{};
            try parseBaseRuleConfig(rule_node, &rc.base, cfg, "rules.max_anytype_params");
            if (rule_node.get("max")) |n| {
                const max = n.getInteger() orelse return ConfigError.InvalidConfig;
                if (max < 0) return ConfigError.InvalidConfig;
                rc.max = @intCast(max);
            }
            rules_cfg.max_anytype_params = rc;
        },
        .no_silent_error_handling => try parseBaseOnlyRule("no_silent_error_handling", Config.NoSilentErrorHandlingConfig, rules_cfg, rule_node, cfg, "rules.no_silent_error_handling"),
        .discard_assignment => try parseBaseOnlyRule("discard_assignment", Config.DiscardAssignmentConfig, rules_cfg, rule_node, cfg, "rules.discard_assignment"),
        .catch_unreachable => try parseBaseOnlyRule("catch_unreachable", Config.CatchUnreachableConfig, rules_cfg, rule_node, cfg, "rules.catch_unreachable"),
        .orelse_unreachable => try parseBaseOnlyRule("orelse_unreachable", Config.OrelseUnreachableConfig, rules_cfg, rule_node, cfg, "rules.orelse_unreachable"),
        .unwrap_optional => try parseBaseOnlyRule("unwrap_optional", Config.UnwrapOptionalConfig, rules_cfg, rule_node, cfg, "rules.unwrap_optional"),
        .suspicious_cast_chain => try parseBaseOnlyRule("suspicious_cast_chain", Config.SuspiciousCastChainConfig, rules_cfg, rule_node, cfg, "rules.suspicious_cast_chain"),
        .no_anyerror_return => try parseBaseOnlyRule("no_anyerror_return", Config.NoAnyerrorReturnConfig, rules_cfg, rule_node, cfg, "rules.no_anyerror_return"),
        .defer_return_invalid => try parseBaseOnlyRule("defer_return_invalid", Config.DeferReturnInvalidConfig, rules_cfg, rule_node, cfg, "rules.defer_return_invalid"),
        .unused_allocator => try parseBaseOnlyRule("unused_allocator", Config.UnusedAllocatorConfig, rules_cfg, rule_node, cfg, "rules.unused_allocator"),
        .global_allocator_in_lib => try parseBaseOnlyRule("global_allocator_in_lib", Config.GlobalAllocatorInLibConfig, rules_cfg, rule_node, cfg, "rules.global_allocator_in_lib"),
        .no_do_not_optimize_away => try parseBaseOnlyRule("no_do_not_optimize_away", Config.NoDoNotOptimizeAwayConfig, rules_cfg, rule_node, cfg, "rules.no_do_not_optimize_away"),
        .duplicated_code => {
            var rc = Config.DuplicatedCodeConfig{};
            try parseBaseRuleConfig(rule_node, &rc.base, cfg, "rules.duplicated_code");
            if (try parsePositiveIntField(rule_node, "min_lines")) |n| rc.min_lines = n;
            if (try parsePositiveIntField(rule_node, "min_statements")) |n| rc.min_statements = n;
            if (try parsePositiveIntField(rule_node, "min_tokens")) |n| rc.min_tokens = n;
            if (try parsePositiveIntField(rule_node, "min_similarity_percent")) |n| {
                if (n > 100) return ConfigError.InvalidConfig;
                rc.min_similarity_percent = n;
            }
            if (try parsePositiveIntField(rule_node, "min_fuzzy_lines")) |n| rc.min_fuzzy_lines = n;
            if (try parsePositiveIntField(rule_node, "max_reports_per_file")) |n| rc.max_reports_per_file = n;
            rules_cfg.duplicated_code = rc;
        },
        .no_anytype_io_params => {
            var rc = Config.NoAnytypeIoParamsConfig{};
            try parseBaseRuleConfig(rule_node, &rc.base, cfg, "rules.no_anytype_io_params");
            if (rule_node.get("io_param_aliases")) |n| {
                rc.io_param_aliases = try parseStringArray(allocator, n, cfg, "rules.no_anytype_io_params.io_param_aliases");
            }
            if (rule_node.get("allow_types")) |n| {
                rc.allow_types = try parseStringArray(allocator, n, cfg, "rules.no_anytype_io_params.allow_types");
            }
            rules_cfg.no_anytype_io_params = rc;
        },
    }
}

/// Load configuration from TOML file.
/// If file is missing, defaults are used.
pub fn loadConfig(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ParseError!Config {
    var cfg = Config{};

    const cwd = std.Io.Dir.cwd();
    const source = cwd.readFileAlloc(io, path, allocator, .limited(8 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return cfg,
        else => {
            std.log.err("Failed reading config {s}: {}", .{ path, err });
            return ConfigError.InvalidConfig;
        },
    };
    defer allocator.free(source);

    var root = ztoml.parseString(allocator, source) catch |err| {
        std.log.err("Failed to parse config {s}: {}", .{ path, err });
        return ConfigError.InvalidConfig;
    };
    defer root.deinit(allocator);

    const root_table = root.getTable() orelse return ConfigError.InvalidConfig;

    // First-pass parse strict_config to decide behavior of following validations.
    if (root.get("strict_config")) |n| {
        cfg.strict_config = n.getBoolean() orelse cfg.strict_config;
    }

    try ensureKnownKeys(root_table, &.{ "version", "strict_config", "strict_exit", "fail_on_warning", "scan", "output", "rules" }, cfg, "root");

    if (root.get("version")) |n| {
        if (n.getInteger()) |v| {
            if (v < 1) return ConfigError.InvalidConfig;
            cfg.version = @intCast(v);
        } else {
            try configFail(cfg, "version must be integer", .{});
        }
    }

    if (root.get("strict_exit")) |n| {
        if (n.getBoolean()) |v| cfg.strict_exit = v else try configFail(cfg, "strict_exit must be boolean", .{});
    }

    if (root.get("fail_on_warning")) |n| {
        if (n.getBoolean()) |v| cfg.fail_on_warning = v else try configFail(cfg, "fail_on_warning must be boolean", .{});
    }

    if (root.get("scan")) |scan_node| {
        const scan_table = scan_node.getTable() orelse return ConfigError.InvalidConfig;
        try ensureKnownKeys(scan_table, &.{ "include", "exclude", "skip_tests" }, cfg, "scan");

        if (scan_node.get("include")) |n| {
            cfg.scan.include = try parseStringArray(allocator, n, cfg, "scan.include");
        }
        if (scan_node.get("exclude")) |n| {
            cfg.scan.exclude = try parseStringArray(allocator, n, cfg, "scan.exclude");
        }
        if (scan_node.get("skip_tests")) |n| {
            if (n.getBoolean()) |v| cfg.scan.skip_tests = v else try configFail(cfg, "scan.skip_tests must be boolean", .{});
        }
    }

    if (root.get("output")) |output_node| {
        const output_table = output_node.getTable() orelse return ConfigError.InvalidConfig;
        try ensureKnownKeys(output_table, &.{"format"}, cfg, "output");

        if (output_node.get("format")) |n| {
            const v = n.getString() orelse return ConfigError.InvalidConfig;
            if (!std.mem.eql(u8, v, "text") and !std.mem.eql(u8, v, "json")) {
                try configFail(cfg, "output.format must be text or json", .{});
            } else {
                cfg.output.format = try allocator.dupe(u8, v);
            }
        }
    }

    if (root.get("rules")) |rules_node| {
        const rules_table = rules_node.getTable() orelse return ConfigError.InvalidConfig;
        var it = rules_table.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const rule_node: *const ztoml.Value = entry.value_ptr;

            if (!rule_node.isTable()) {
                try configFail(cfg, "rules.{s} must be a table", .{key});
                continue;
            }
            try parseRuleEntry(allocator, cfg, &cfg.rules, key, rule_node);
        }
    }

    return cfg;
}
