const std = @import("std");
const Diagnostic = @import("../diagnostic.zig").Diagnostic;
const Summary = @import("../diagnostic.zig").Summary;

/// JSON DTO for diagnostic output
const JsonDiagnostic = struct {
    rule_id: []const u8,
    severity: []const u8,
    path: []const u8,
    line: usize,
    column: usize,
    message: []const u8,
};

const JsonSummary = struct {
    files_scanned: usize,
    diagnostics: usize,
    errors: usize,
    warnings: usize,
};

const JsonReport = struct {
    ok: bool,
    summary: JsonSummary,
    diagnostics: []const JsonDiagnostic,
};

/// Write diagnostics in JSON format using std.json.Stringify.value
/// This ensures proper escaping and valid JSON output
pub fn writeJson(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    diagnostics: []const Diagnostic,
    summary: Summary,
) !void {
    // Allocate temporary array for JSON DTOs
    const items = try allocator.alloc(JsonDiagnostic, diagnostics.len);
    defer allocator.free(items);

    // Map Diagnostic -> JsonDiagnostic
    for (diagnostics, items) |src, *dst| {
        dst.* = .{
            .rule_id = src.rule_id,
            .severity = src.severity.toString(),
            .path = src.path,
            .line = src.line,
            .column = src.column,
            .message = src.message,
        };
    }

    // Build the report struct
    const report = JsonReport{
        .ok = summary.errors == 0,
        .summary = .{
            .files_scanned = summary.files_scanned,
            .diagnostics = summary.diagnostics,
            .errors = summary.errors,
            .warnings = summary.warnings,
        },
        .diagnostics = items,
    };

    // Serialize using std.json.Stringify.value with pretty printing
    try std.json.Stringify.value(report, .{
        .whitespace = .indent_2,
    }, writer);

    // Add trailing newline
    try writer.writeAll("\n");
}
