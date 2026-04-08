const std = @import("std");
const RuleContext = @import("root.zig").RuleContext;
const locations = @import("../ast/locations.zig");
const Severity = @import("../diagnostic.zig").Severity;

/// Common AST traversal utilities for rules
pub const AstUtils = struct {
    /// Iterate over all nodes and apply callback for matching tags
    pub fn forEachNodeWithTag(
        ctx: *RuleContext,
        comptime tag: std.zig.Ast.Node.Tag,
        comptime callback: fn (*RuleContext, std.zig.Ast.Node.Index) anyerror!void,
    ) !void {
        const ast = ctx.file.ast;
        const tags = ast.nodes.items(.tag);

        for (tags, 0..) |t, i| {
            if (t == tag) {
                const node: std.zig.Ast.Node.Index = @enumFromInt(i);
                if (!ctx.shouldSkipNode(node)) {
                    ctx.traceNodeBestEffort(2, node, "visit");
                    try callback(ctx, node);
                }
            }
        }
    }

    /// Iterate over all nodes and apply callback for multiple matching tags
    pub fn forEachNodeWithTags(
        ctx: *RuleContext,
        comptime tag_list: []const std.zig.Ast.Node.Tag,
        comptime callback: fn (*RuleContext, std.zig.Ast.Node.Index, std.zig.Ast.Node.Tag) anyerror!void,
    ) !void {
        const ast = ctx.file.ast;
        const tags = ast.nodes.items(.tag);

        for (tags, 0..) |t, i| {
            inline for (tag_list) |target_tag| {
                if (t == target_tag) {
                    const node: std.zig.Ast.Node.Index = @enumFromInt(i);
                    if (!ctx.shouldSkipNode(node)) {
                        ctx.traceNodeBestEffort(2, node, "visit");
                        try callback(ctx, node, t);
                    }
                }
            }
        }
    }

    /// Check if a node's tag matches
    pub fn isNodeTag(ast: std.zig.Ast, node: std.zig.Ast.Node.Index, tag: std.zig.Ast.Node.Tag) bool {
        const tags = ast.nodes.items(.tag);
        return tags[@intFromEnum(node)] == tag;
    }

    /// Get the tag of a node
    pub fn getNodeTag(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) std.zig.Ast.Node.Tag {
        const tags = ast.nodes.items(.tag);
        return tags[@intFromEnum(node)];
    }

    /// Get the identifier name for a node
    pub fn getIdentifierName(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) ?[]const u8 {
        if (!isNodeTag(ast, node, .identifier)) return null;
        const tokens = ast.nodes.items(.main_token);
        const token = tokens[@intFromEnum(node)];
        return ast.tokenSlice(token);
    }

    /// Check if an identifier is underscore
    pub fn isUnderscoreIdentifier(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) bool {
        const name = getIdentifierName(ast, node) orelse return false;
        return std.mem.eql(u8, name, "_");
    }

    /// Get the field name from a field access node
    pub fn getFieldName(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) ?[]const u8 {
        if (!isNodeTag(ast, node, .field_access)) return null;
        const data = ast.nodeData(node);
        const field_token = data.node_and_token[1];
        return ast.tokenSlice(field_token);
    }

    /// Get node data safely
    pub fn getNodeData(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) std.zig.Ast.Node.Data {
        return ast.nodeData(node);
    }

    /// Get RHS of binary expressions (catch, orelse, assign, etc.)
    pub fn getRhs(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) std.zig.Ast.Node.Index {
        const data = ast.nodeData(node);
        return data.node_and_node[1];
    }

    /// Get LHS of binary expressions
    pub fn getLhs(ast: std.zig.Ast, node: std.zig.Ast.Node.Index) std.zig.Ast.Node.Index {
        const data = ast.nodeData(node);
        return data.node_and_node[0];
    }

    /// Add diagnostic with node location
    pub fn addDiagnosticAtNode(
        ctx: *RuleContext,
        rule_id: []const u8,
        severity: Severity,
        node: std.zig.Ast.Node.Index,
        message: []const u8,
    ) !void {
        const ast = ctx.file.ast;
        const loc = locations.getNodeLocation(ast, node, ctx.file.content);
        try ctx.addDiagnostic(rule_id, severity, loc.line, loc.column, message);
    }
};

/// String utilities for rules
pub const StringUtils = struct {
    /// Check if string is in list
    pub fn isInList(name: []const u8, list: []const []const u8) bool {
        for (list) |item| {
            if (std.mem.eql(u8, name, item)) return true;
        }
        return false;
    }

    /// Check if string starts with any prefix in list
    pub fn startsWithAny(name: []const u8, prefixes: []const []const u8) bool {
        for (prefixes) |prefix| {
            if (std.mem.startsWith(u8, name, prefix)) return true;
        }
        return false;
    }
};

/// Configuration utilities for rules
pub const ConfigUtils = struct {
    /// Get severity from rule config
    pub fn getSeverity(config: anytype, default_severity: Severity) Severity {
        if (config) |c| {
            return Severity.fromString(c.base.severity) orelse default_severity;
        }
        return default_severity;
    }
};
