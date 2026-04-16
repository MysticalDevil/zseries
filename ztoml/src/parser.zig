const std = @import("std");
const lexer_zig = @import("lexer.zig");
const value_zig = @import("value.zig");
const errors = @import("error.zig");
const Lexer = lexer_zig.Lexer;
const Token = lexer_zig.Token;
const TokenType = lexer_zig.TokenType;
const Value = value_zig.Value;
const ErrorSet = errors.ErrorSet;
const Error = errors.Error;
const makeError = errors.makeError;
const makeParseError = errors.makeParseError;

/// Parser state
const Parser = struct {
    lexer: Lexer,
    current_token: Token,
    allocator: std.mem.Allocator,
    had_error: bool = false,
    /// Current table context for key-value pairs (points into root table tree)
    current_table: ?*Value = null,

    fn init(allocator: std.mem.Allocator, source: []const u8) ErrorSet!Parser {
        var lexer = Lexer.init(source);
        const first_token = try lexer.nextToken();
        return .{
            .lexer = lexer,
            .current_token = first_token,
            .allocator = allocator,
        };
    }

    fn advance(self: *Parser) ErrorSet!void {
        self.current_token = try self.lexer.nextToken();
    }

    fn expect(self: *Parser, token_type: TokenType) ErrorSet!void {
        if (self.current_token.type != token_type) {
            return ErrorSet.UnexpectedToken;
        }
        try self.advance();
    }

    fn skipNewlines(self: *Parser) ErrorSet!void {
        while (self.current_token.type == .NewLine) {
            try self.advance();
        }
    }

    /// Parse a TOML document
    fn parse(self: *Parser) ErrorSet!Value {
        var root = Value.table(self.allocator);
        errdefer root.deinit(self.allocator);

        // Initially, key-value pairs go into root table
        self.current_table = &root;

        while (self.current_token.type != .EOF) {
            try self.skipNewlines();
            if (self.current_token.type == .EOF) break;

            if (self.current_token.type == .LeftBracket) {
                // Table header updates current_table
                try self.parseTableHeader(&root);
            } else if (self.current_token.type == .LeftDoubleBracket) {
                // Array table header also updates current_table
                try self.parseArrayTableHeader(&root);
            } else {
                // Parse key-value into current table context
                const table = self.current_table orelse return ErrorSet.InvalidTable;
                try self.parseKeyValue(table);
            }
        }

        return root;
    }

    /// Parse a key (bare key or quoted key)
    fn parseKey(self: *Parser) ErrorSet![]const u8 {
        const token = self.current_token;
        switch (token.type) {
            .Identifier, .String => {
                try self.advance();
                // For strings, remove quotes
                if (token.type == .String) {
                    if (token.text.len >= 2) {
                        return token.text[1 .. token.text.len - 1];
                    }
                }
                return token.text;
            },
            .Integer => {
                // Bare keys can be integers
                try self.advance();
                return token.text;
            },
            else => return ErrorSet.InvalidSyntax,
        }
    }

    /// Parse a dotted key (e.g., "a.b.c")
    fn parseDottedKey(self: *Parser) ErrorSet![][]const u8 {
        var parts: std.ArrayList([]const u8) = .empty;
        errdefer parts.deinit(self.allocator);

        while (true) {
            const key_part = try self.parseKey();
            try parts.append(self.allocator, key_part);

            if (self.current_token.type == .Dot) {
                try self.advance();
            } else {
                break;
            }
        }

        return parts.toOwnedSlice(self.allocator);
    }

    /// Parse a value
    fn parseValue(self: *Parser) ErrorSet!Value {
        const token = self.current_token;

        switch (token.type) {
            .String => {
                try self.advance();
                // Remove quotes from string
                if (token.text.len >= 2) {
                    const inner = token.text[1 .. token.text.len - 1];
                    return Value.string(inner);
                }
                return Value.string(token.text);
            },
            .Integer => {
                try self.advance();
                const n = try parseInteger(token.text);
                return Value.integer(n);
            },
            .Float => {
                try self.advance();
                const f = try parseFloat(token.text);
                return Value.float(f);
            },
            .Boolean => {
                try self.advance();
                const b = std.mem.eql(u8, token.text, "true");
                return Value.boolean(b);
            },
            .LeftBracket => {
                return try self.parseArray();
            },
            .LeftBrace => {
                return try self.parseInlineTable();
            },
            else => {
                return ErrorSet.UnexpectedToken;
            },
        }
    }

    /// Parse an array
    fn parseArray(self: *Parser) ErrorSet!Value {
        try self.expect(.LeftBracket);

        var arr = Value.array(self.allocator);
        errdefer arr.deinit(self.allocator);

        while (self.current_token.type != .RightBracket) {
            try self.skipNewlines();
            if (self.current_token.type == .RightBracket) break;

            const value = try self.parseValue();
            try arr.append(self.allocator, value);

            try self.skipNewlines();
            if (self.current_token.type == .Comma) {
                try self.advance();
                try self.skipNewlines();
                // Allow trailing comma
                if (self.current_token.type == .RightBracket) break;
            }
        }

        try self.expect(.RightBracket);
        return arr;
    }

    /// Parse an inline table
    fn parseInlineTable(self: *Parser) ErrorSet!Value {
        try self.expect(.LeftBrace);

        var table = Value.table(self.allocator);
        errdefer table.deinit(self.allocator);

        while (self.current_token.type != .RightBrace) {
            const key = try self.parseKey();
            try self.expect(.Equal);
            const value = try self.parseValue();
            try table.put(key, value);

            if (self.current_token.type == .Comma) {
                try self.advance();
            } else if (self.current_token.type != .RightBrace) {
                return ErrorSet.UnexpectedToken;
            }
        }

        try self.expect(.RightBrace);
        return table;
    }

    /// Parse a key-value pair
    fn parseKeyValue(self: *Parser, root: *Value) ErrorSet!void {
        const key_parts = try self.parseDottedKey();
        defer self.allocator.free(key_parts);

        try self.expect(.Equal);

        const value = try self.parseValue();

        const table = try self.ensureTablePath(root, key_parts[0 .. key_parts.len - 1]);
        switch (table.*) {
            .Table => |*t| try t.put(key_parts[key_parts.len - 1], value),
            else => return ErrorSet.InvalidTable,
        }
    }

    fn parseHeaderKeyParts(self: *Parser, open: TokenType, close: TokenType) ErrorSet![][]const u8 {
        try self.expect(open);

        const key_parts = try self.parseDottedKey();
        errdefer self.allocator.free(key_parts);

        try self.expect(close);
        return key_parts;
    }

    /// Parse a table header like [table]
    fn parseTableHeader(self: *Parser, root: *Value) ErrorSet!void {
        const key_parts = try self.parseHeaderKeyParts(.LeftBracket, .RightBracket);
        defer self.allocator.free(key_parts);

        self.current_table = try self.ensureTablePath(root, key_parts);
    }

    /// Parse an array of tables header like [[table]]
    fn parseArrayTableHeader(self: *Parser, root: *Value) ErrorSet!void {
        const key_parts = try self.parseHeaderKeyParts(.LeftDoubleBracket, .RightDoubleBracket);
        defer self.allocator.free(key_parts);

        const parent_parts = key_parts[0 .. key_parts.len - 1];
        const last_key = key_parts[key_parts.len - 1];

        const current = try self.ensureTablePath(root, parent_parts);

        // Add new table to array
        switch (current.*) {
            .Table => |*t| {
                const existing = t.getPtr(last_key);
                if (existing) |e| {
                    if (e.isArray()) {
                        const new_table = Value.table(self.allocator);
                        try e.append(self.allocator, new_table);
                        // Set current to the newly added table
                        self.current_table = &e.Array.items[e.Array.items.len - 1];
                    } else {
                        // Need to convert to array
                        return ErrorSet.InvalidTable;
                    }
                } else {
                    var arr = Value.array(self.allocator);
                    const new_table = Value.table(self.allocator);
                    try arr.append(self.allocator, new_table);
                    try t.put(last_key, arr);
                    // The new table inside the array is the current context
                    const arr_ptr = t.getPtr(last_key) orelse return ErrorSet.InvalidTable;
                    self.current_table = &arr_ptr.Array.items[0];
                }
            },
            else => return ErrorSet.InvalidTable,
        }
    }

    fn ensureTablePath(self: *Parser, root: *Value, parts: []const []const u8) ErrorSet!*Value {
        var current: *Value = root;
        for (parts) |part| {
            switch (current.*) {
                .Table => |*t| {
                    if (t.getPtr(part)) |existing| {
                        if (!existing.isTable()) return ErrorSet.InvalidTable;
                        current = existing;
                    } else {
                        try t.put(part, Value.table(self.allocator));
                        current = t.getPtr(part) orelse return ErrorSet.InvalidTable;
                    }
                },
                else => return ErrorSet.InvalidTable,
            }
        }
        return current;
    }
};

/// Parse an integer from text
fn parseInteger(text: []const u8) ErrorSet!i64 {
    var buf: [64]u8 = undefined;
    const cleaned = try stripUnderscores(text, &buf);

    return std.fmt.parseInt(i64, cleaned, 0) catch return ErrorSet.InvalidNumber;
}

/// Parse a float from text
fn parseFloat(text: []const u8) ErrorSet!f64 {
    var buf: [64]u8 = undefined;
    const cleaned = try stripUnderscores(text, &buf);

    // Handle special values
    if (std.mem.eql(u8, cleaned, "inf") or std.mem.eql(u8, cleaned, "+inf")) {
        return std.math.inf(f64);
    }
    if (std.mem.eql(u8, cleaned, "-inf")) {
        return -std.math.inf(f64);
    }
    if (std.mem.eql(u8, cleaned, "nan") or std.mem.eql(u8, cleaned, "+nan")) {
        return std.math.nan(f64);
    }
    if (std.mem.eql(u8, cleaned, "-nan")) {
        return -std.math.nan(f64);
    }

    return std.fmt.parseFloat(f64, cleaned) catch return ErrorSet.InvalidNumber;
}

fn stripUnderscores(text: []const u8, buf: *[64]u8) ErrorSet![]const u8 {
    if (text.len > buf.len) return ErrorSet.InvalidNumber;

    var i: usize = 0;
    for (text) |c| {
        if (c != '_') {
            buf[i] = c;
            i += 1;
        }
    }
    return buf[0..i];
}

/// Parse TOML source into a Value tree
pub fn parse(allocator: std.mem.Allocator, source: []const u8) ErrorSet!Value {
    var parser = try Parser.init(allocator, source);
    return try parser.parse();
}

/// Parse TOML from a file
pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) ErrorSet!Value {
    const file = std.fs.cwd().openFile(path, .{}) catch return ErrorSet.IoError;
    defer file.close();

    const source = file.readToEndAlloc(allocator, 1024 * 1024 * 10) catch return ErrorSet.IoError;
    defer allocator.free(source);

    return parse(allocator, source);
}
