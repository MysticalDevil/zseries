const std = @import("std");
const ErrorSet = @import("error.zig").ErrorSet;

/// TOML Value type representing any TOML value
pub const Value = union(enum) {
    String: []const u8,
    Integer: i64,
    Float: f64,
    Boolean: bool,
    Datetime: DatetimeValue,
    Array: std.ArrayList(Value),
    Table: std.StringHashMap(Value),

    pub const DatetimeValue = struct {
        /// The raw datetime string from TOML
        raw: []const u8,
        /// Type of datetime
        kind: Kind,

        pub const Kind = enum {
            LocalDate, // 1979-05-27
            LocalTime, // 07:32:00
            LocalDateTime, // 1979-05-27T07:32:00
            OffsetDateTime, // 1979-05-27T07:32:00Z or with offset
        };
    };

    /// Create a string value
    pub fn string(s: []const u8) Value {
        return .{ .String = s };
    }

    /// Create an integer value
    pub fn integer(i: i64) Value {
        return .{ .Integer = i };
    }

    /// Create a float value
    pub fn float(f: f64) Value {
        return .{ .Float = f };
    }

    /// Create a boolean value
    pub fn boolean(b: bool) Value {
        return .{ .Boolean = b };
    }

    /// Create a datetime value
    pub fn datetime(raw: []const u8, kind: DatetimeValue.Kind) Value {
        return .{ .Datetime = .{ .raw = raw, .kind = kind } };
    }

    /// Create an empty array
    pub fn array(allocator: std.mem.Allocator) Value {
        _ = allocator;
        return .{ .Array = std.ArrayList(Value).empty };
    }

    /// Create an empty table
    pub fn table(allocator: std.mem.Allocator) Value {
        return .{ .Table = std.StringHashMap(Value).init(allocator) };
    }

    /// Deallocate this value and all children
    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .Array => |*arr| {
                arr.deinit(allocator);
            },
            .Table => |*map| {
                var it = map.iterator();
                while (it.next()) |entry| {
                    entry.value_ptr.deinit(allocator);
                }
                map.deinit();
            },
            else => {},
        }
    }

    /// Get string value or null
    pub fn getString(self: Value) ?[]const u8 {
        return switch (self) {
            .String => |s| s,
            else => null,
        };
    }

    /// Get integer value or null
    pub fn getInteger(self: Value) ?i64 {
        return switch (self) {
            .Integer => |i| i,
            else => null,
        };
    }

    /// Get float value or null
    pub fn getFloat(self: Value) ?f64 {
        return switch (self) {
            .Float => |f| f,
            else => null,
        };
    }

    /// Get boolean value or null
    pub fn getBoolean(self: Value) ?bool {
        return switch (self) {
            .Boolean => |b| b,
            else => null,
        };
    }

    /// Get array value or null
    pub fn getArray(self: Value) ?std.ArrayList(Value) {
        return switch (self) {
            .Array => |arr| arr,
            else => null,
        };
    }

    /// Get table value or null
    pub fn getTable(self: Value) ?std.StringHashMap(Value) {
        return switch (self) {
            .Table => |t| t,
            else => null,
        };
    }

    /// Get value from table by key
    pub fn get(self: Value, key: []const u8) ?*const Value {
        return switch (self) {
            .Table => |*t| t.getPtr(key),
            else => null,
        };
    }

    /// Get value at array index
    pub fn at(self: Value, index: usize) ?*const Value {
        return switch (self) {
            .Array => |*arr| if (index < arr.items.len) &arr.items[index] else null,
            else => null,
        };
    }

    /// Add item to array
    pub fn append(self: *Value, gpa: std.mem.Allocator, value: Value) ErrorSet!void {
        switch (self.*) {
            .Array => |*arr| try arr.append(gpa, value),
            else => return ErrorSet.InvalidArray,
        }
    }

    /// Insert key-value into table
    pub fn put(self: *Value, key: []const u8, value: Value) ErrorSet!void {
        switch (self.*) {
            .Table => |*t| try t.put(key, value),
            else => return ErrorSet.InvalidTable,
        }
    }

    /// Check if value is a string
    pub fn isString(self: Value) bool {
        return self == .String;
    }

    /// Check if value is an integer
    pub fn isInteger(self: Value) bool {
        return self == .Integer;
    }

    /// Check if value is a float
    pub fn isFloat(self: Value) bool {
        return self == .Float;
    }

    /// Check if value is a boolean
    pub fn isBoolean(self: Value) bool {
        return self == .Boolean;
    }

    /// Check if value is a datetime
    pub fn isDatetime(self: Value) bool {
        return self == .Datetime;
    }

    /// Check if value is an array
    pub fn isArray(self: Value) bool {
        return self == .Array;
    }

    /// Check if value is a table
    pub fn isTable(self: Value) bool {
        return self == .Table;
    }
};
