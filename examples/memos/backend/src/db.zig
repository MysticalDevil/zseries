const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const Db = struct {
    db: *c.sqlite3,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Db {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path.ptr, &db);
        if (rc != c.SQLITE_OK) {
            if (db) |ptr| {
                const err_msg = std.mem.span(c.sqlite3_errmsg(ptr));
                std.log.err("sqlite3_open failed: {s}", .{err_msg});
                _ = c.sqlite3_close(ptr);
            }
            return error.SqliteOpenFailed;
        }
        var self = Db{ .db = db.?, .allocator = allocator };
        try self.exec(
            \\CREATE TABLE IF NOT EXISTS users (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  username TEXT UNIQUE NOT NULL,
            \\  password_hash TEXT NOT NULL
            \\);
            \\CREATE TABLE IF NOT EXISTS memos (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  user_id INTEGER NOT NULL,
            \\  content TEXT NOT NULL,
            \\  updated_at INTEGER NOT NULL
            \\);
        );
        return self;
    }

    pub fn deinit(self: *Db) void {
        _ = c.sqlite3_close(self.db);
    }

    pub fn exec(self: *Db, sql: []const u8) !void {
        var err_msg: [*c]u8 = null;
        const rc = c.sqlite3_exec(self.db, sql.ptr, null, null, &err_msg);
        if (rc != c.SQLITE_OK) {
            if (err_msg) |msg| {
                std.log.err("SQL error: {s}", .{std.mem.span(msg)});
                c.sqlite3_free(msg);
            }
            return error.SqliteExecFailed;
        }
    }

    pub fn createUser(self: *Db, username: []const u8, password_hash: []const u8) !i64 {
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "INSERT INTO users (username, password_hash) VALUES (?, ?)";
        var rc = c.sqlite3_prepare_v2(self.db, sql, @intCast(sql.len), &stmt, null);
        if (rc != c.SQLITE_OK) return error.SqlitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, username.ptr, @intCast(username.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 2, password_hash.ptr, @intCast(password_hash.len), c.SQLITE_STATIC);

        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_DONE) return error.SqliteInsertFailed;
        return c.sqlite3_last_insert_rowid(self.db);
    }

    pub fn findUser(self: *Db, username: []const u8) !?User {
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT id, password_hash FROM users WHERE username = ?";
        var rc = c.sqlite3_prepare_v2(self.db, sql, @intCast(sql.len), &stmt, null);
        if (rc != c.SQLITE_OK) return error.SqlitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, username.ptr, @intCast(username.len), c.SQLITE_STATIC);

        rc = c.sqlite3_step(stmt);
        if (rc == c.SQLITE_DONE) return null;
        if (rc != c.SQLITE_ROW) return error.SqliteQueryFailed;

        return User{
            .id = c.sqlite3_column_int64(stmt, 0),
            .username = try self.allocator.dupe(u8, username),
            .password_hash = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(stmt, 1))),
        };
    }

    pub fn listMemos(self: *Db, user_id: i64) ![]Memo {
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT id, content, updated_at FROM memos WHERE user_id = ? ORDER BY updated_at DESC";
        var rc = c.sqlite3_prepare_v2(self.db, sql, @intCast(sql.len), &stmt, null);
        if (rc != c.SQLITE_OK) return error.SqlitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        _ = c.sqlite3_bind_int64(stmt, 1, user_id);

        var list = std.ArrayList(Memo).empty;
        errdefer {
            for (list.items) |*m| m.deinit(self.allocator);
            list.deinit(self.allocator);
        }

        while (true) {
            rc = c.sqlite3_step(stmt);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return error.SqliteQueryFailed;
            try list.append(self.allocator, Memo{
                .id = c.sqlite3_column_int64(stmt, 0),
                .content = try self.allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(stmt, 1))),
                .updated_at = c.sqlite3_column_int64(stmt, 2),
            });
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn createMemo(self: *Db, user_id: i64, content: []const u8, updated_at: i64) !i64 {
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "INSERT INTO memos (user_id, content, updated_at) VALUES (?, ?, ?)";
        var rc = c.sqlite3_prepare_v2(self.db, sql, @intCast(sql.len), &stmt, null);
        if (rc != c.SQLITE_OK) return error.SqlitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_int64(stmt, 1, user_id);
        _ = c.sqlite3_bind_text(stmt, 2, content.ptr, @intCast(content.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_int64(stmt, 3, updated_at);

        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_DONE) return error.SqliteInsertFailed;
        return c.sqlite3_last_insert_rowid(self.db);
    }

    pub fn updateMemo(self: *Db, id: i64, user_id: i64, content: []const u8, updated_at: i64) !bool {
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "UPDATE memos SET content = ?, updated_at = ? WHERE id = ? AND user_id = ?";
        var rc = c.sqlite3_prepare_v2(self.db, sql, @intCast(sql.len), &stmt, null);
        if (rc != c.SQLITE_OK) return error.SqlitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, content.ptr, @intCast(content.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_int64(stmt, 2, updated_at);
        _ = c.sqlite3_bind_int64(stmt, 3, id);
        _ = c.sqlite3_bind_int64(stmt, 4, user_id);

        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_DONE) return error.SqliteUpdateFailed;
        return c.sqlite3_changes(self.db) > 0;
    }

    pub fn deleteMemo(self: *Db, id: i64, user_id: i64) !bool {
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "DELETE FROM memos WHERE id = ? AND user_id = ?";
        var rc = c.sqlite3_prepare_v2(self.db, sql, @intCast(sql.len), &stmt, null);
        if (rc != c.SQLITE_OK) return error.SqlitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_int64(stmt, 1, id);
        _ = c.sqlite3_bind_int64(stmt, 2, user_id);

        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_DONE) return error.SqliteDeleteFailed;
        return c.sqlite3_changes(self.db) > 0;
    }
};

pub const User = struct {
    id: i64,
    username: []const u8,
    password_hash: []const u8,

    pub fn deinit(self: *User, allocator: std.mem.Allocator) void {
        allocator.free(self.username);
        allocator.free(self.password_hash);
    }
};

pub const Memo = struct {
    id: i64,
    content: []const u8,
    updated_at: i64,

    pub fn deinit(self: *Memo, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }
};
