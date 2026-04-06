const std = @import("std");

/// Ignore directives for a file
pub const IgnoreDirectives = struct {
    file_ignores: std.StringHashMap(void),
    line_ignores: std.AutoHashMap(usize, std.StringHashMap(void)),

    pub fn init(allocator: std.mem.Allocator) IgnoreDirectives {
        return .{
            .file_ignores = std.StringHashMap(void).init(allocator),
            .line_ignores = std.AutoHashMap(usize, std.StringHashMap(void)).init(allocator),
        };
    }

    pub fn deinit(self: *IgnoreDirectives) void {
        // Free file_ignores keys
        var file_key_it = self.file_ignores.keyIterator();
        while (file_key_it.next()) |key| {
            self.file_ignores.allocator.free(key.*);
        }
        self.file_ignores.deinit();

        // Free line_ignores keys and values
        var line_it = self.line_ignores.iterator();
        while (line_it.next()) |entry| {
            var rule_key_it = entry.value_ptr.keyIterator();
            while (rule_key_it.next()) |key| {
                entry.value_ptr.allocator.free(key.*);
            }
            entry.value_ptr.deinit();
        }
        self.line_ignores.deinit();
    }

    /// Parse ignore directives from source content
    pub fn parse(allocator: std.mem.Allocator, content: []const u8) !IgnoreDirectives {
        var directives = IgnoreDirectives.init(allocator);
        errdefer directives.deinit();

        var lines = std.mem.splitScalar(u8, content, '\n');
        var line_no: usize = 1;

        while (lines.next()) |line| : (line_no += 1) {
            // Look for zlint:ignore or zlint:file-ignore
            if (std.mem.indexOf(u8, line, "zlint:")) |idx| {
                const directive = line[idx + 6 ..];
                if (std.mem.startsWith(u8, directive, "ignore ")) {
                    const rule_id = std.mem.trim(u8, directive[7..], " \t\r");
                    try directives.addLineIgnore(line_no, rule_id);
                } else if (std.mem.startsWith(u8, directive, "file-ignore ")) {
                    const rule_id = std.mem.trim(u8, directive[12..], " \t\r");
                    try directives.addFileIgnore(rule_id);
                }
            }
        }

        return directives;
    }

    fn addFileIgnore(self: *IgnoreDirectives, rule_id: []const u8) !void {
        const owned = try self.file_ignores.allocator.dupe(u8, rule_id);
        try self.file_ignores.put(owned, {});
    }

    fn addLineIgnore(self: *IgnoreDirectives, line_no: usize, rule_id: []const u8) !void {
        const gop = try self.line_ignores.getOrPut(line_no);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.StringHashMap(void).init(self.file_ignores.allocator);
        }
        const owned = try self.file_ignores.allocator.dupe(u8, rule_id);
        try gop.value_ptr.put(owned, {});
    }

    /// Check if a rule should be suppressed at a given line
    pub fn shouldSuppress(self: IgnoreDirectives, rule_id: []const u8, line_no: usize) bool {
        // Check file-level ignores
        if (self.file_ignores.contains(rule_id)) return true;

        // Check line-level ignores
        if (self.line_ignores.get(line_no)) |rules| {
            if (rules.contains(rule_id)) return true;
        }

        return false;
    }
};
