const std = @import("std");
const zcli = @import("zcli");
const Diagnostic = @import("../diagnostic.zig").Diagnostic;
const Summary = @import("../diagnostic.zig").Summary;
const Severity = @import("../diagnostic.zig").Severity;

// ASCII icons instead of Nerd Fonts
const ICON_FILE = "";
const ICON_ERROR = "[X]";
const ICON_WARNING = "[!]";
const ICON_SUCCESS = "[OK]";
const ICON_X = "[X]";

/// Write diagnostics in text format with rich colors using Nerd Fonts
pub fn writeText(writer: anytype, diagnostics: []const Diagnostic, summary: Summary, use_color: bool) !void {
    // Group diagnostics by file for better organization
    var current_path: ?[]const u8 = null;

    for (diagnostics) |d| {
        // Print file header when path changes
        const path_changed = if (current_path) |path|
            !std.mem.eql(u8, path, d.path)
        else
            true;

        if (path_changed) {
            if (current_path != null) {
                try writer.writeByte('\n');
            }
            current_path = d.path;
            try writer.writeByte('\n');
            try zcli.color.writeStyled(writer, use_color, .command, ICON_FILE);
            try writer.writeByte(' ');
            try zcli.color.writeStyled(writer, use_color, .value, d.path);
            try writer.writeByte('\n');
        }

        // Indent and show location
        try writer.writeAll("  ");
        try zcli.color.writeStyled(writer, use_color, .muted, "[");
        try writer.print("{d}", .{d.line});
        try writer.writeByte(':');
        try writer.print("{d}", .{d.column});
        try zcli.color.writeStyled(writer, use_color, .muted, "]");
        try writer.writeAll("  ");

        // Write severity with icon and color
        switch (d.severity) {
            .err => {
                try zcli.color.writeStyled(writer, use_color, .title, ICON_ERROR);
                try writer.writeByte(' ');
                try zcli.color.writeStyled(writer, use_color, .title, "error");
            },
            .warning => {
                try zcli.color.writeStyled(writer, use_color, .flag, ICON_WARNING);
                try writer.writeByte(' ');
                try zcli.color.writeStyled(writer, use_color, .flag, "warning");
            },
        }
        try writer.writeAll("  ");

        // Write rule_id in accent color
        try zcli.color.writeStyled(writer, use_color, .accent, d.rule_id);
        try writer.writeAll(": ");

        // Write message
        try writer.print("{s}\n", .{d.message});
    }

    // Write summary with rich formatting
    if (summary.diagnostics > 0) {
        try writer.writeByte('\n');
        try zcli.color.writeStyled(writer, use_color, .heading, "═══════════════════════════════════════════════════════\n");
        try writer.writeByte('\n');

        // Summary header
        try zcli.color.writeStyled(writer, use_color, .heading, "  Summary\n");
        try writer.writeByte('\n');

        // Files scanned
        try writer.writeAll("  ");
        try zcli.color.writeStyled(writer, use_color, .muted, "Files scanned:");
        try writer.writeAll(" ");
        try zcli.color.writeStyled(writer, use_color, .value, try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{summary.files_scanned}));
        try writer.writeByte('\n');

        // Total diagnostics
        try writer.writeAll("  ");
        try zcli.color.writeStyled(writer, use_color, .muted, "Total issues:");
        try writer.writeAll(" ");
        try zcli.color.writeStyled(writer, use_color, .value, try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{summary.diagnostics}));
        try writer.writeByte('\n');

        // Errors
        try writer.writeAll("  ");
        try zcli.color.writeStyled(writer, use_color, .title, ICON_ERROR);
        try writer.writeAll(" Errors:   ");
        if (summary.errors > 0) {
            try zcli.color.writeStyled(writer, use_color, .title, try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{summary.errors}));
        } else {
            try zcli.color.writeStyled(writer, use_color, .muted, "0");
        }
        try writer.writeByte('\n');

        // Warnings
        try writer.writeAll("  ");
        try zcli.color.writeStyled(writer, use_color, .flag, ICON_WARNING);
        try writer.writeAll(" Warnings: ");
        if (summary.warnings > 0) {
            try zcli.color.writeStyled(writer, use_color, .flag, try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{summary.warnings}));
        } else {
            try zcli.color.writeStyled(writer, use_color, .muted, "0");
        }
        try writer.writeByte('\n');

        // Status indicator
        try writer.writeByte('\n');
        if (summary.errors > 0) {
            try zcli.color.writeStyled(writer, use_color, .title, "  ");
            try zcli.color.writeStyled(writer, use_color, .title, ICON_X);
            try zcli.color.writeStyled(writer, use_color, .title, " Check failed with errors\n");
        } else if (summary.warnings > 0) {
            try zcli.color.writeStyled(writer, use_color, .flag, "  ");
            try zcli.color.writeStyled(writer, use_color, .flag, ICON_WARNING);
            try zcli.color.writeStyled(writer, use_color, .flag, " Check completed with warnings\n");
        } else {
            try zcli.color.writeStyled(writer, use_color, .command, "  ");
            try zcli.color.writeStyled(writer, use_color, .command, ICON_SUCCESS);
            try zcli.color.writeStyled(writer, use_color, .command, " All checks passed\n");
        }

        try writer.writeByte('\n');
        try zcli.color.writeStyled(writer, use_color, .heading, "═══════════════════════════════════════════════════════\n");
    } else {
        // No diagnostics - show success message
        try writer.writeByte('\n');
        try zcli.color.writeStyled(writer, use_color, .heading, "═══════════════════════════════════════════════════════\n");
        try writer.writeByte('\n');
        try zcli.color.writeStyled(writer, use_color, .command, "  ");
        try zcli.color.writeStyled(writer, use_color, .command, ICON_SUCCESS);
        try writer.writeByte(' ');
        try zcli.color.writeStyled(writer, use_color, .command, "All checks passed");
        try writer.writeByte('\n');
        try writer.writeAll("  ");
        try zcli.color.writeStyled(writer, use_color, .muted, try std.fmt.allocPrint(std.heap.page_allocator, "Scanned {d} files, no issues found", .{summary.files_scanned}));
        try writer.writeByte('\n');
        try writer.writeByte('\n');
        try zcli.color.writeStyled(writer, use_color, .heading, "═══════════════════════════════════════════════════════\n");
    }
}
