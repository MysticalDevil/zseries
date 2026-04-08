const std = @import("std");

/// Severity level for diagnostics
pub const Severity = enum {
    err,
    warning,
    help,

    pub fn fromString(s: []const u8) ?Severity {
        if (std.mem.eql(u8, s, "error")) return .err;
        if (std.mem.eql(u8, s, "warning")) return .warning;
        if (std.mem.eql(u8, s, "help")) return .help;
        return null;
    }

    pub fn toString(self: Severity) []const u8 {
        return switch (self) {
            .err => "error",
            .warning => "warning",
            .help => "help",
        };
    }
};

/// A diagnostic message
pub const Diagnostic = struct {
    rule_id: []const u8,
    severity: Severity,
    path: []const u8,
    line: usize,
    column: usize,
    message: []const u8,
};

/// Summary of linting results
pub const Summary = struct {
    files_scanned: usize = 0,
    diagnostics: usize = 0,
    errors: usize = 0,
    warnings: usize = 0,
    helps: usize = 0,

    pub fn addDiagnostic(self: *Summary, severity: Severity) void {
        self.diagnostics += 1;
        switch (severity) {
            .err => self.errors += 1,
            .warning => self.warnings += 1,
            .help => self.helps += 1,
        }
    }
};

/// Collection of diagnostics
pub const DiagnosticCollection = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Diagnostic),

    pub fn init(allocator: std.mem.Allocator) DiagnosticCollection {
        return .{
            .allocator = allocator,
            .items = std.ArrayList(Diagnostic).empty,
        };
    }

    pub fn deinit(self: *DiagnosticCollection) void {
        for (self.items.items) |d| {
            self.allocator.free(d.message);
        }
        self.items.deinit(self.allocator);
    }

    pub fn add(self: *DiagnosticCollection, diagnostic: Diagnostic) !void {
        const msg_copy = try self.allocator.dupe(u8, diagnostic.message);
        try self.items.append(self.allocator, .{
            .rule_id = diagnostic.rule_id,
            .severity = diagnostic.severity,
            .path = diagnostic.path,
            .line = diagnostic.line,
            .column = diagnostic.column,
            .message = msg_copy,
        });
    }

    pub fn getSummary(self: DiagnosticCollection) Summary {
        var summary = Summary{};
        for (self.items.items) |d| {
            summary.addDiagnostic(d.severity);
        }
        return summary;
    }
};

test "severity supports help string conversion" {
    try std.testing.expectEqual(Severity.help, Severity.fromString("help").?);
    try std.testing.expectEqualStrings("help", Severity.help.toString());
}

test "summary counts help separately" {
    var summary = Summary{};
    summary.addDiagnostic(.err);
    summary.addDiagnostic(.warning);
    summary.addDiagnostic(.help);

    try std.testing.expectEqual(@as(usize, 3), summary.diagnostics);
    try std.testing.expectEqual(@as(usize, 1), summary.errors);
    try std.testing.expectEqual(@as(usize, 1), summary.warnings);
    try std.testing.expectEqual(@as(usize, 1), summary.helps);
}
