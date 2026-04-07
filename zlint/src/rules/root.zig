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

/// Helper to add a rule if enabled
fn addRuleIfEnabled(
    rules: *std.ArrayList(Rule),
    allocator: std.mem.Allocator,
    comptime name: []const u8,
    comptime module: type,
    maybe_config: ?Config.BaseRuleConfig,
) !void {
    const enabled = if (maybe_config) |cfg| cfg.enabled else true;
    if (enabled) {
        try rules.append(allocator, .{
            .name = name,
            .run = module.run,
        });
    }
}

/// Get enabled rules based on configuration
pub fn getEnabledRules(config: Config, allocator: std.mem.Allocator) ![]Rule {
    var rules = std.ArrayList(Rule).empty;

    try addRuleIfEnabled(&rules, allocator, "discarded-result", @import("discarded_result.zig"), if (config.rules.discarded_result) |c| c.base else null);
    try addRuleIfEnabled(&rules, allocator, "max-anytype-params", @import("max_anytype_params.zig"), if (config.rules.max_anytype_params) |c| c.base else null);
    try addRuleIfEnabled(&rules, allocator, "no-do-not-optimize-away", @import("no_do_not_optimize_away.zig"), if (config.rules.no_do_not_optimize_away) |c| c.base else null);
    try addRuleIfEnabled(&rules, allocator, "no-empty-catch", @import("no_empty_catch.zig"), if (config.rules.no_empty_catch) |c| c.base else null);
    try addRuleIfEnabled(&rules, allocator, "catch-unreachable", @import("catch_unreachable.zig"), if (config.rules.catch_unreachable) |c| c.base else null);
    try addRuleIfEnabled(&rules, allocator, "defer-return-invalid", @import("defer_return_invalid.zig"), if (config.rules.defer_return_invalid) |c| c.base else null);
    try addRuleIfEnabled(&rules, allocator, "unused-allocator", @import("unused_allocator.zig"), if (config.rules.unused_allocator) |c| c.base else null);
    try addRuleIfEnabled(&rules, allocator, "global-allocator-in-lib", @import("global_allocator_in_lib.zig"), if (config.rules.global_allocator_in_lib) |c| c.base else null);
    try addRuleIfEnabled(&rules, allocator, "duplicated-code", @import("duplicated_code.zig"), if (config.rules.duplicated_code) |c| c.base else null);

    return rules.toOwnedSlice(allocator);
}
