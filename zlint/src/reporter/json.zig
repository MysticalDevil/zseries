const std = @import("std");
const Diagnostic = @import("../diagnostic.zig").Diagnostic;
const Summary = @import("../diagnostic.zig").Summary;

/// Write diagnostics in JSON format
pub fn writeJson(writer: *std.Io.Writer, diagnostics: []const Diagnostic, summary: Summary) !void {
    const ok = summary.errors == 0;

    try writer.writeAll("{\n");
    try writer.print("  \"ok\": {s},\n", .{if (ok) "true" else "false"});

    // Summary
    try writer.writeAll("  \"summary\": {\n");
    try writer.print("    \"files_scanned\": {d},\n", .{summary.files_scanned});
    try writer.print("    \"diagnostics\": {d},\n", .{summary.diagnostics});
    try writer.print("    \"errors\": {d},\n", .{summary.errors});
    try writer.print("    \"warnings\": {d}\n", .{summary.warnings});
    try writer.writeAll("  },\n");

    // Diagnostics
    try writer.writeAll("  \"diagnostics\": [\n");
    for (diagnostics, 0..) |d, i| {
        try writer.writeAll("    {\n");
        try writer.print("      \"rule_id\": \"{s}\",\n", .{d.rule_id});
        try writer.print("      \"severity\": \"{s}\",\n", .{@tagName(d.severity)});
        try writer.print("      \"path\": \"{s}\",\n", .{d.path});
        try writer.print("      \"line\": {d},\n", .{d.line});
        try writer.print("      \"column\": {d},\n", .{d.column});
        try writer.print("      \"message\": \"{s}\"\n", .{d.message});
        try writer.writeAll("    }");
        if (i < diagnostics.len - 1) {
            try writer.writeAll(",");
        }
        try writer.writeAll("\n");
    }
    try writer.writeAll("  ]\n");
    try writer.writeAll("}\n");
}
