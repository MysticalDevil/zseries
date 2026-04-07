const std = @import("std");
const zcli = @import("zcli");
const Diagnostic = @import("../diagnostic.zig").Diagnostic;
const Summary = @import("../diagnostic.zig").Summary;

const ICON_ERROR = "[X]";
const ICON_WARNING = "[!]";
const ICON_SUCCESS = "[OK]";

/// Write diagnostics in text format
/// Input must be pre-sorted by path for proper grouping
pub fn writeText(
    writer: *std.Io.Writer,
    diagnostics: []const Diagnostic,
    summary: Summary,
    use_color: bool,
) !void {
    // Group diagnostics by file
    var current_path: ?[]const u8 = null;
    for (diagnostics) |d| {
        const path_changed = if (current_path) |path| !std.mem.eql(u8, path, d.path) else true;
        if (path_changed) {
            if (current_path != null) try writer.writeByte('\n');
            current_path = d.path;
            try writer.writeByte('\n');
            try zcli.color.writeStyled(writer, use_color, .value, d.path);
            try writer.writeByte('\n');
        }
        try writeDiagnostic(writer, d, use_color);
    }

    // Summary
    try writeSummary(writer, summary, use_color);
}

fn writeDiagnostic(writer: *std.Io.Writer, d: Diagnostic, use_color: bool) !void {
    const style: zcli.color.Style = switch (d.severity) {
        .err => .title,
        .warning => .flag,
    };
    const icon = switch (d.severity) {
        .err => ICON_ERROR,
        .warning => ICON_WARNING,
    };
    const text = switch (d.severity) {
        .err => "error",
        .warning => "warning",
    };

    try writer.writeAll("  [");
    try writer.print("{d}:{d}", .{ d.line, d.column });
    try zcli.color.writeStyled(writer, use_color, .muted, "]  ");
    try zcli.color.writeStyled(writer, use_color, style, icon);
    try writer.writeByte(' ');
    try zcli.color.writeStyled(writer, use_color, style, text);
    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, use_color, .accent, d.rule_id);
    try writer.writeAll(": ");
    try writer.print("{s}\n", .{d.message});
}

fn writeSummary(writer: *std.Io.Writer, s: Summary, use_color: bool) !void {
    try writeLine(writer, "═══════════════════════════════════════════════════════", .heading, use_color);

    const has_errors = s.errors > 0;
    const has_warnings = s.warnings > 0;
    const has_issues = s.diagnostics > 0;

    if (has_issues) {
        try writer.writeByte('\n');
        try zcli.color.writeStyled(writer, use_color, .heading, "  Summary\n\n");

        var buf: [64]u8 = undefined;
        try writeMetric(writer, "Files scanned:", try std.fmt.bufPrint(&buf, "{d}", .{s.files_scanned}), .value, use_color);
        try writeMetric(writer, "Total issues:", try std.fmt.bufPrint(&buf, "{d}", .{s.diagnostics}), .value, use_color);

        const err_str = if (has_errors) try std.fmt.bufPrint(&buf, "{d}", .{s.errors}) else "0";
        try writeMetricWithIcon(writer, ICON_ERROR, "Errors:", err_str, if (has_errors) .title else .muted, use_color);

        const warn_str = if (has_warnings) try std.fmt.bufPrint(&buf, "{d}", .{s.warnings}) else "0";
        try writeMetricWithIcon(writer, ICON_WARNING, "Warnings:", warn_str, if (has_warnings) .flag else .muted, use_color);

        try writer.writeByte('\n');
        const status_icon = if (has_errors) ICON_ERROR else ICON_WARNING;
        const status_text = if (has_errors) "Check failed with errors" else "Check completed with warnings";
        const status_style = if (has_errors) zcli.color.Style.title else zcli.color.Style.flag;
        try writer.writeAll("  ");
        try zcli.color.writeStyled(writer, use_color, status_style, status_icon);
        try writer.writeByte(' ');
        try zcli.color.writeStyled(writer, use_color, status_style, status_text);
        try writer.writeByte('\n');
    } else {
        try writer.writeByte('\n');
        try writer.writeAll("  ");
        try zcli.color.writeStyled(writer, use_color, .command, ICON_SUCCESS);
        try zcli.color.writeStyled(writer, use_color, .command, " All checks passed\n");
        try writer.writeAll("  ");
        var buf: [64]u8 = undefined;
        try zcli.color.writeStyled(writer, use_color, .muted, try std.fmt.bufPrint(&buf, "Scanned {d} files, no issues found", .{s.files_scanned}));
        try writer.writeByte('\n');
    }

    try writer.writeByte('\n');
    try writeLine(writer, "═══════════════════════════════════════════════════════", .heading, use_color);
}

fn writeLine(writer: *std.Io.Writer, text: []const u8, style: zcli.color.Style, use_color: bool) !void {
    try zcli.color.writeStyled(writer, use_color, style, text);
    try writer.writeByte('\n');
}

fn writeMetric(writer: *std.Io.Writer, label: []const u8, value: []const u8, style: zcli.color.Style, use_color: bool) !void {
    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, use_color, .muted, label);
    try writer.writeByte(' ');
    try zcli.color.writeStyled(writer, use_color, style, value);
    try writer.writeByte('\n');
}

fn writeMetricWithIcon(
    writer: *std.Io.Writer,
    icon: []const u8,
    label: []const u8,
    value: []const u8,
    style: zcli.color.Style,
    use_color: bool,
) !void {
    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, use_color, style, icon);
    try writer.writeByte(' ');
    try zcli.color.writeStyled(writer, use_color, .muted, label);
    try writer.writeAll(" ");
    try zcli.color.writeStyled(writer, use_color, style, value);
    try writer.writeByte('\n');
}
