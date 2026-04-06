const std = @import("std");

pub const TokenType = enum {
    // Literals
    String,
    Integer,
    Float,
    Boolean,
    // Symbols
    LeftBracket, // [
    RightBracket, // ]
    LeftDoubleBracket, // [[
    RightDoubleBracket, // ]]
    LeftBrace, // {
    RightBrace, // }
    Equal, // =
    Comma, // ,
    Dot, // .
    NewLine, // \n
    // Identifiers and keywords
    Identifier,
    // Special
    EOF,
};

pub const Token = struct {
    type: TokenType,
    text: []const u8,
    line: usize,
    column: usize,
};

pub const ErrorSet = error{
    InvalidString,
    InvalidEscapeSequence,
    InvalidSyntax,
    OutOfMemory,
};

pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: usize,
    column: usize,

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 1,
        };
    }

    fn peek(self: *const Lexer) u8 {
        if (self.pos >= self.source.len) return 0;
        return self.source[self.pos];
    }

    fn peekNext(self: *const Lexer, offset: usize) u8 {
        const idx = self.pos + offset;
        if (idx >= self.source.len) return 0;
        return self.source[idx];
    }

    fn advance(self: *Lexer) void {
        if (self.pos >= self.source.len) return;
        const c = self.source[self.pos];
        self.pos += 1;
        if (c == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
    }

    fn skipWhitespace(self: *Lexer) void {
        while (true) {
            const c = self.peek();
            if (c == ' ' or c == '\t' or c == '\r') {
                self.advance();
            } else {
                break;
            }
        }
    }

    fn skipComment(self: *Lexer) void {
        if (self.peek() == '#') {
            while (self.peek() != '\n' and self.peek() != 0) {
                self.advance();
            }
        }
    }

    fn readString(self: *Lexer, delimiter: u8) ErrorSet!Token {
        const start_line = self.line;
        const start_col = self.column;
        const start_pos = self.pos;

        self.advance(); // consume opening quote

        while (self.peek() != delimiter) {
            if (self.peek() == 0) {
                return ErrorSet.InvalidString;
            }
            if (self.peek() == '\n') {
                return ErrorSet.InvalidString;
            }
            if (self.peek() == '\\' and delimiter == '"') {
                self.advance();
                if (self.peek() == 0) {
                    return ErrorSet.InvalidEscapeSequence;
                }
            }
            self.advance();
        }

        self.advance(); // consume closing quote

        return .{
            .type = .String,
            .text = self.source[start_pos..self.pos],
            .line = start_line,
            .column = start_col,
        };
    }

    fn readNumber(self: *Lexer) Token {
        const start_line = self.line;
        const start_col = self.column;
        const start_pos = self.pos;

        // Check for hex/oct/bin prefixes
        if (self.peek() == '0') {
            const next = self.peekNext(1);
            if (next == 'x' or next == 'o' or next == 'b') {
                self.advance();
                self.advance();
                const prefix = if (next == 'x') "0123456789abcdefABCDEF" else if (next == 'o') "01234567" else "01";
                while (std.mem.indexOfScalar(u8, prefix, self.peek()) != null) {
                    self.advance();
                }
                return .{
                    .type = .Integer,
                    .text = self.source[start_pos..self.pos],
                    .line = start_line,
                    .column = start_col,
                };
            }
        }

        // Integer or float
        var is_float = false;
        while (true) {
            const c = self.peek();
            if (c >= '0' and c <= '9') {
                self.advance();
            } else if (c == '_' and (self.peekNext(1) >= '0' and self.peekNext(1) <= '9')) {
                self.advance(); // underscore separator
            } else if (c == '.' and !is_float and (self.peekNext(1) >= '0' and self.peekNext(1) <= '9')) {
                is_float = true;
                self.advance();
            } else if ((c == 'e' or c == 'E') and is_float) {
                self.advance();
                if (self.peek() == '+' or self.peek() == '-') {
                    self.advance();
                }
            } else if ((c == 'e' or c == 'E') and !is_float) {
                // Check if this is scientific notation
                const next = self.peekNext(1);
                if ((next >= '0' and next <= '9') or next == '+' or next == '-') {
                    is_float = true;
                    self.advance();
                    if (self.peek() == '+' or self.peek() == '-') {
                        self.advance();
                    }
                } else {
                    break;
                }
            } else {
                break;
            }
        }

        // Check for special float values
        if (!is_float) {
            const text = self.source[start_pos..self.pos];
            if (std.mem.eql(u8, text, "inf") or std.mem.eql(u8, text, "+inf") or
                std.mem.eql(u8, text, "-inf") or std.mem.eql(u8, text, "nan") or
                std.mem.eql(u8, text, "+nan") or std.mem.eql(u8, text, "-nan"))
            {
                is_float = true;
            }
        }

        return .{
            .type = if (is_float) .Float else .Integer,
            .text = self.source[start_pos..self.pos],
            .line = start_line,
            .column = start_col,
        };
    }

    fn readIdentifier(self: *Lexer) Token {
        const start_line = self.line;
        const start_col = self.column;
        const start_pos = self.pos;

        while (true) {
            const c = self.peek();
            if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
                (c >= '0' and c <= '9') or c == '_' or c == '-')
            {
                self.advance();
            } else {
                break;
            }
        }

        const text = self.source[start_pos..self.pos];

        // Check for boolean literals
        if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false")) {
            return .{
                .type = .Boolean,
                .text = text,
                .line = start_line,
                .column = start_col,
            };
        }

        // Check for special float values
        if (std.mem.eql(u8, text, "inf") or std.mem.eql(u8, text, "nan")) {
            return .{
                .type = .Float,
                .text = text,
                .line = start_line,
                .column = start_col,
            };
        }

        return .{
            .type = .Identifier,
            .text = text,
            .line = start_line,
            .column = start_col,
        };
    }

    pub fn nextToken(self: *Lexer) ErrorSet!Token {
        self.skipWhitespace();

        // Skip comments
        if (self.peek() == '#') {
            self.skipComment();
            self.skipWhitespace();
        }

        const line = self.line;
        const col = self.column;

        if (self.pos >= self.source.len) {
            return .{
                .type = .EOF,
                .text = "",
                .line = line,
                .column = col,
            };
        }

        const c = self.peek();

        // Check for double brackets first
        if (c == '[') {
            if (self.peekNext(1) == '[') {
                self.advance();
                self.advance();
                return .{
                    .type = .LeftDoubleBracket,
                    .text = "[[",
                    .line = line,
                    .column = col,
                };
            }
            self.advance();
            return .{
                .type = .LeftBracket,
                .text = "[",
                .line = line,
                .column = col,
            };
        }

        if (c == ']') {
            if (self.peekNext(1) == ']') {
                self.advance();
                self.advance();
                return .{
                    .type = .RightDoubleBracket,
                    .text = "]][",
                    .line = line,
                    .column = col,
                };
            }
            self.advance();
            return .{
                .type = .RightBracket,
                .text = "]",
                .line = line,
                .column = col,
            };
        }

        // Single character tokens
        switch (c) {
            '{' => {
                self.advance();
                return .{ .type = .LeftBrace, .text = "{", .line = line, .column = col };
            },
            '}' => {
                self.advance();
                return .{ .type = .RightBrace, .text = "}", .line = line, .column = col };
            },
            '=' => {
                self.advance();
                return .{ .type = .Equal, .text = "=", .line = line, .column = col };
            },
            ',' => {
                self.advance();
                return .{ .type = .Comma, .text = ",", .line = line, .column = col };
            },
            '.' => {
                self.advance();
                return .{ .type = .Dot, .text = ".", .line = line, .column = col };
            },
            '\n' => {
                self.advance();
                return .{ .type = .NewLine, .text = "\n", .line = line, .column = col };
            },
            '"', '\'' => {
                return try self.readString(c);
            },
            '0'...'9', '+', '-' => {
                return self.readNumber();
            },
            else => {
                if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_') {
                    return self.readIdentifier();
                }
                return ErrorSet.InvalidSyntax;
            },
        }
    }
};

/// Tokenize entire source and return array of tokens
pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) ErrorSet![]Token {
    var tokens: std.ArrayList(Token) = .empty;
    errdefer tokens.deinit(allocator);

    var lexer = Lexer.init(source);
    while (true) {
        const token = try lexer.nextToken();
        try tokens.append(allocator, token);
        if (token.type == .EOF) break;
    }

    return tokens.toOwnedSlice(allocator);
}
