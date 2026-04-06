const std = @import("std");
const zcli = @import("zcli");
const Diagnostic = @import("../diagnostic.zig").Diagnostic;
const Summary = @import("../diagnostic.zig").Summary;
const Severity = @import("../diagnostic.zig").Severity;

/// Write diagnostics in text format with colors
pub fn writeText(writer: anytype, diagnostics: []const Diagnostic, summary: Summary, use_color: bool) !void {
    for (diagnostics) |d| {
        // Write path:line:column
        try zcli.color.writeStyled(writer, use_color, .value, d.path);
        try writer.writeByte(':');
        try writer.print("{d}", .{d.line});
        try writer.writeByte(':');
        try writer.print("{d}", .{d.column});
        try writer.writeByte(':');
        try writer.writeByte(' ');

        // Write severity with color
        const style: zcli.color.Style = switch (d.severity) {
            .err => .title,
            .warning => .flag,
        };
        try zcli.color.writeStyled(writer, use_color, style, @tagName(d.severity));
        try writer.writeByte(':');
        try writer.writeByte(' ');

        // Write rule_id
        try zcli.color.writeStyled(writer, use_color, .accent, d.rule_id);
        try writer.writeByte(':');
        try writer.writeByte(' ');

        // Write message
        try writer.print("{s}\n", .{d.message});
    }

    if (summary.diagnostics > 0) {
        try writer.writeByte('\n');
        try zcli.color.writeStyled(writer, use_color, .heading, "Summary: ");
        try writer.print("{d} diagnostic(s), ", .{summary.diagnostics});

        try zcli.color.writeStyled(writer, use_color, .title, try std.fmt.allocPrint(std.heap.page_allocator, "{d} error(s)", .{summary.errors}));
        try writer.writeAll(", ");
        try zcli.color.writeStyled(writer, use_color, .flag, try std.fmt.allocPrint(std.heap.page_allocator, "{d} warning(s)", .{summary.warnings}));
        try writer.writeByte('\n');
    }
}
