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
        const zai_code = rule_id_map.get(rule_id) orelse rule_id;
        if (self.ignores.shouldSuppress(zai_code, line)) return;
        if (self.ignores.shouldSuppress(rule_id, line)) return;

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
    name: []const u8,
    run: *const fn (*RuleContext) anyerror!void,
};

/// Rule definition table - drives rule registration
const RuleDef = struct {
    name: []const u8,
    module: type,
    getBase: *const fn (Config) ?Config.BaseRuleConfig,
};

/// Rule registration table - add new rules here
const RULE_TABLE: []const RuleDef = &.{
    .{ .name = "discarded-result", .module = @import("discarded_result.zig"), .getBase = struct {
        fn get(c: Config) ?Config.BaseRuleConfig {
            return if (c.rules.discarded_result) |r| r.base else null;
        }
    }.get },
    .{ .name = "max-anytype-params", .module = @import("max_anytype_params.zig"), .getBase = struct {
        fn get(c: Config) ?Config.BaseRuleConfig {
            return if (c.rules.max_anytype_params) |r| r.base else null;
        }
    }.get },
    .{ .name = "no-do-not-optimize-away", .module = @import("no_do_not_optimize_away.zig"), .getBase = struct {
        fn get(c: Config) ?Config.BaseRuleConfig {
            return if (c.rules.no_do_not_optimize_away) |r| r.base else null;
        }
    }.get },
    .{ .name = "no-empty-catch", .module = @import("no_empty_catch.zig"), .getBase = struct {
        fn get(c: Config) ?Config.BaseRuleConfig {
            return if (c.rules.no_empty_catch) |r| r.base else null;
        }
    }.get },
    .{ .name = "catch-unreachable", .module = @import("catch_unreachable.zig"), .getBase = struct {
        fn get(c: Config) ?Config.BaseRuleConfig {
            return if (c.rules.catch_unreachable) |r| r.base else null;
        }
    }.get },
    .{ .name = "defer-return-invalid", .module = @import("defer_return_invalid.zig"), .getBase = struct {
        fn get(c: Config) ?Config.BaseRuleConfig {
            return if (c.rules.defer_return_invalid) |r| r.base else null;
        }
    }.get },
    .{ .name = "unused-allocator", .module = @import("unused_allocator.zig"), .getBase = struct {
        fn get(c: Config) ?Config.BaseRuleConfig {
            return if (c.rules.unused_allocator) |r| r.base else null;
        }
    }.get },
    .{ .name = "global-allocator-in-lib", .module = @import("global_allocator_in_lib.zig"), .getBase = struct {
        fn get(c: Config) ?Config.BaseRuleConfig {
            return if (c.rules.global_allocator_in_lib) |r| r.base else null;
        }
    }.get },
    .{ .name = "duplicated-code", .module = @import("duplicated_code.zig"), .getBase = struct {
        fn get(c: Config) ?Config.BaseRuleConfig {
            return if (c.rules.duplicated_code) |r| r.base else null;
        }
    }.get },
};

/// Get enabled rules based on configuration - table-driven
pub fn getEnabledRules(config: Config, allocator: std.mem.Allocator) ![]Rule {
    var rules = std.ArrayList(Rule).empty;

    inline for (RULE_TABLE) |def| {
        const base = def.getBase(config);
        const enabled = if (base) |b| b.enabled else true;
        if (enabled) {
            try rules.append(allocator, .{
                .name = def.name,
                .run = def.module.run,
            });
        }
    }

    return rules.toOwnedSlice(allocator);
}
