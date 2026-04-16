const std = @import("std");
const zest = @import("zest");
const AuthState = @import("auth.zig").AuthState;
const Db = @import("db.zig").Db;
const time = @import("time.zig");

const RegisterReq = struct {
    username: []const u8,
    password: []const u8,
};

const LoginReq = struct {
    username: []const u8,
    password: []const u8,
};

const MemoReq = struct {
    content: []const u8,
};

pub fn registerHandler(ctx: *zest.Context) !void {
    const req = try ctx.bodyJson(RegisterReq) orelse {
        try ctx.jsonStatus(zest.Status.bad_request, .{ .@"error" = "invalid json" });
        return;
    };
    const state: *AuthState = @ptrCast(@alignCast(ctx.get("auth_state").?));
    const hash = try AuthState.hashPassword(ctx.allocator, req.password);
    defer ctx.allocator.free(hash);

    const user_id = state.db.createUser(req.username, hash) catch {
        try ctx.jsonStatus(zest.Status.conflict, .{ .@"error" = "username exists" });
        return;
    };

    try ctx.jsonStatus(zest.Status.created, .{ .id = user_id, .username = req.username });
}

pub fn loginHandler(ctx: *zest.Context) !void {
    const req = try ctx.bodyJson(LoginReq) orelse {
        try ctx.jsonStatus(zest.Status.bad_request, .{ .@"error" = "invalid json" });
        return;
    };
    const state: *AuthState = @ptrCast(@alignCast(ctx.get("auth_state").?));
    var user = try state.db.findUser(req.username) orelse {
        try ctx.jsonStatus(zest.Status.unauthorized, .{ .@"error" = "invalid credentials" });
        return;
    };
    defer user.deinit(ctx.allocator);

    const hash = try AuthState.hashPassword(ctx.allocator, req.password);
    defer ctx.allocator.free(hash);
    if (!std.mem.eql(u8, hash, user.password_hash)) {
        try ctx.jsonStatus(zest.Status.unauthorized, .{ .@"error" = "invalid credentials" });
        return;
    }

    const token = try state.generateToken(user.username, user.id);
    defer state.allocator.free(token);
    try ctx.jsonStatus(zest.Status.ok, .{ .token = token });
}

fn getUserId(ctx: *zest.Context) i64 {
    const ptr = ctx.get("user_id").?;
    return @intCast(@intFromPtr(ptr));
}

pub fn listMemosHandler(ctx: *zest.Context) !void {
    const state: *AuthState = @ptrCast(@alignCast(ctx.get("auth_state").?));
    const user_id = getUserId(ctx);
    const memos = try state.db.listMemos(user_id);
    defer {
        for (memos) |*m| m.deinit(ctx.allocator);
        ctx.allocator.free(memos);
    }

    const MemoResp = struct {
        id: i64,
        content: []const u8,
        updated_at: i64,
    };

    var arr = try ctx.allocator.alloc(MemoResp, memos.len);
    defer ctx.allocator.free(arr);
    for (memos, 0..) |m, i| {
        arr[i] = .{ .id = m.id, .content = m.content, .updated_at = m.updated_at };
    }
    try ctx.jsonStatus(zest.Status.ok, arr);
}

pub fn createMemoHandler(ctx: *zest.Context) !void {
    const req = try ctx.bodyJson(MemoReq) orelse {
        try ctx.jsonStatus(zest.Status.bad_request, .{ .@"error" = "invalid json" });
        return;
    };
    const state: *AuthState = @ptrCast(@alignCast(ctx.get("auth_state").?));
    const user_id = getUserId(ctx);
    const now = time.nowMillis(state.io);
    const id = try state.db.createMemo(user_id, req.content, now);
    try ctx.jsonStatus(zest.Status.created, .{ .id = id, .content = req.content });
}

pub fn updateMemoHandler(ctx: *zest.Context) !void {
    const req = try ctx.bodyJson(MemoReq) orelse {
        try ctx.jsonStatus(zest.Status.bad_request, .{ .@"error" = "invalid json" });
        return;
    };
    const state: *AuthState = @ptrCast(@alignCast(ctx.get("auth_state").?));
    const user_id = getUserId(ctx);
    const id_str = ctx.param("id") orelse {
        try ctx.jsonStatus(zest.Status.bad_request, .{ .@"error" = "missing id" });
        return;
    };
    const id = std.fmt.parseInt(i64, id_str, 10) catch {
        try ctx.jsonStatus(zest.Status.bad_request, .{ .@"error" = "invalid id" });
        return;
    };
    const now = time.nowMillis(state.io);
    const ok = try state.db.updateMemo(id, user_id, req.content, now);
    if (!ok) {
        try ctx.jsonStatus(zest.Status.not_found, .{ .@"error" = "not found" });
        return;
    }
    try ctx.jsonStatus(zest.Status.ok, .{ .id = id, .content = req.content });
}

pub fn deleteMemoHandler(ctx: *zest.Context) !void {
    const state: *AuthState = @ptrCast(@alignCast(ctx.get("auth_state").?));
    const user_id = getUserId(ctx);
    const id_str = ctx.param("id") orelse {
        try ctx.jsonStatus(zest.Status.bad_request, .{ .@"error" = "missing id" });
        return;
    };
    const id = std.fmt.parseInt(i64, id_str, 10) catch {
        try ctx.jsonStatus(zest.Status.bad_request, .{ .@"error" = "invalid id" });
        return;
    };
    const ok = try state.db.deleteMemo(id, user_id);
    if (!ok) {
        try ctx.jsonStatus(zest.Status.not_found, .{ .@"error" = "not found" });
        return;
    }
    try ctx.jsonStatus(zest.Status.no_content, .{});
}

pub fn staticFileHandler(ctx: *zest.Context) !void {
    const allocator = ctx.allocator;
    const io = ctx.io;
    const dir = std.Io.Dir.cwd();
    const base = "../frontend/dist";

    const sub_path = if (std.mem.eql(u8, ctx.path, "/")) "index.html" else ctx.path;
    const file_path = try std.fs.path.join(allocator, &.{ base, sub_path });
    defer allocator.free(file_path);

    const data = dir.readFileAlloc(io, file_path, allocator, std.Io.Limit.limited(1024 * 1024)) catch |err| {
        if (err == error.FileNotFound or err == error.NotDir) {
            // SPA fallback
            const index_path = try std.fs.path.join(allocator, &.{ base, "index.html" });
            defer allocator.free(index_path);
            const index = dir.readFileAlloc(io, index_path, allocator, std.Io.Limit.limited(1024 * 1024)) catch {
                try ctx.jsonStatus(zest.Status.not_found, .{ .@"error" = "frontend not built" });
                return;
            };
            try ctx.setHeader("Content-Type", "text/html; charset=utf-8");
            try ctx.textStatus(zest.Status.ok, index);
            return;
        }
        return err;
    };

    const ext = std.fs.path.extension(file_path);
    const content_type = if (std.mem.eql(u8, ext, ".js"))
        "application/javascript"
    else if (std.mem.eql(u8, ext, ".css"))
        "text/css"
    else if (std.mem.eql(u8, ext, ".html"))
        "text/html; charset=utf-8"
    else if (std.mem.eql(u8, ext, ".svg"))
        "image/svg+xml"
    else if (std.mem.eql(u8, ext, ".png"))
        "image/png"
    else
        "application/octet-stream";

    try ctx.setHeader("Content-Type", content_type);
    try ctx.textStatus(zest.Status.ok, data);
}
