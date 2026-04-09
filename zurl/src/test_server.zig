const std = @import("std");
const zest = @import("zest");

const LoginPayload = struct {
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
};

const CreateItemPayload = struct {
    title: []const u8,
    content: []const u8,
};

const UpdateItemPayload = struct {
    title: ?[]const u8 = null,
    content: ?[]const u8 = null,
};

const Item = struct {
    id: u32,
    title: []const u8,
    content: []const u8,
    deleted: bool,
};

const State = struct {
    allocator: std.mem.Allocator,
    logged_in: bool,
    next_id: u32,
    items: std.ArrayList(Item),

    fn init(allocator: std.mem.Allocator) State {
        return .{
            .allocator = allocator,
            .logged_in = false,
            .next_id = 1,
            .items = .empty,
        };
    }

    fn deinit(self: *State) void {
        for (self.items.items) |item| {
            self.allocator.free(item.title);
            self.allocator.free(item.content);
        }
        self.items.deinit(self.allocator);
    }

    fn createItem(self: *State, title: []const u8, content: []const u8) !Item {
        const item = Item{
            .id = self.next_id,
            .title = try self.allocator.dupe(u8, title),
            .content = try self.allocator.dupe(u8, content),
            .deleted = false,
        };
        self.next_id += 1;
        try self.items.append(self.allocator, item);
        return item;
    }

    fn getItem(self: *State, id: u32) ?*Item {
        for (self.items.items) |*item| {
            if (item.id == id and !item.deleted) return item;
        }
        return null;
    }
};

var global_state: ?*State = null;
var static_state: ?State = null;

fn state() *State {
    return global_state orelse unreachable;
}

pub fn resetState(allocator: std.mem.Allocator) void {
    if (static_state) |*existing| {
        existing.deinit();
    }
    static_state = State.init(allocator);
    global_state = &static_state.?;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    resetState(allocator);
    defer if (static_state) |*existing| existing.deinit();
    defer {
        static_state = null;
        global_state = null;
    }

    const args = init.minimal.args.toSlice(allocator) catch return error.InvalidArguments;
    defer allocator.free(args);

    const port = try parsePort(args);

    var app = try zest.App.init(allocator, init.io);
    defer app.deinit();

    try app.get("/health", healthHandler);
    try app.post("/session/login", loginHandler);
    try app.post("/session/logout", logoutHandler);
    try app.get("/session/me", meHandler);
    try app.post("/items", createItemHandler);
    try app.get("/items", listItemsHandler);
    try app.get("/items/:id", getItemHandler);
    try app.patch("/items/:id", updateItemHandler);
    try app.delete("/items/:id", deleteItemHandler);
    try app.post("/echo", echoHandler);
    try app.get("/redirect", redirectHandler);
    try app.get("/redirect-target", redirectTargetHandler);

    try app.listen(.{ .ip4 = std.Io.net.Ip4Address.loopback(port) });
}

fn parsePort(args: []const []const u8) !u16 {
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (!std.mem.eql(u8, args[index], "--port")) continue;
        const value = args[index + 1];
        return try std.fmt.parseInt(u16, value, 10);
    }
    return 18081;
}

pub fn healthHandler(ctx: *zest.Context) !void {
    try ctx.jsonStatus(zest.Status.ok, .{ .status = "ok" });
}

pub fn loginHandler(ctx: *zest.Context) !void {
    const body = ctx.bodyText() orelse return validationError(ctx, "Username and password are required.");
    var parsed = try std.json.parseFromSlice(LoginPayload, ctx.allocator, body, .{});
    defer parsed.deinit();

    const username = parsed.value.username orelse return validationError(ctx, "Username and password are required.");
    const password = parsed.value.password orelse return validationError(ctx, "Username and password are required.");

    if (!std.mem.eql(u8, username, "admin") or !std.mem.eql(u8, password, "admin123456")) {
        try ctx.jsonStatus(zest.Status.unauthorized, .{ .@"error" = .{ .code = "unauthenticated", .message = "Invalid credentials." } });
        return;
    }

    state().logged_in = true;
    try ctx.setHeader("Set-Cookie", "zest_session=active; Path=/");
    try ctx.jsonStatus(zest.Status.ok, .{ .data = .{ .id = 1, .username = "admin" } });
}

pub fn logoutHandler(ctx: *zest.Context) !void {
    state().logged_in = false;
    try ctx.setHeader("Set-Cookie", "zest_session=; Path=/");
    try ctx.jsonStatus(zest.Status.ok, .{ .data = .{ .logged_out = true } });
}

pub fn meHandler(ctx: *zest.Context) !void {
    if (!isAuthenticated(ctx)) {
        try ctx.jsonStatus(zest.Status.unauthorized, .{ .@"error" = .{ .code = "unauthenticated", .message = "Authentication required." } });
        return;
    }

    try ctx.jsonStatus(zest.Status.ok, .{ .data = .{ .id = 1, .username = "admin" } });
}

pub fn createItemHandler(ctx: *zest.Context) !void {
    if (!isAuthenticated(ctx)) return unauthorized(ctx);

    const body = ctx.bodyText() orelse return validationError(ctx, "title and content are required");
    var parsed = try std.json.parseFromSlice(CreateItemPayload, ctx.allocator, body, .{});
    defer parsed.deinit();

    const item = try state().createItem(parsed.value.title, parsed.value.content);
    try ctx.jsonStatus(zest.Status.created, .{ .data = .{ .id = item.id, .title = item.title, .content = item.content } });
}

pub fn listItemsHandler(ctx: *zest.Context) !void {
    if (!isAuthenticated(ctx)) return unauthorized(ctx);

    var items = std.ArrayList(struct { id: u32, title: []const u8, content: []const u8 }).empty;
    defer items.deinit(ctx.allocator);
    for (state().items.items) |item| {
        if (item.deleted) continue;
        try items.append(ctx.allocator, .{ .id = item.id, .title = item.title, .content = item.content });
    }
    try ctx.jsonStatus(zest.Status.ok, .{ .data = .{ .items = items.items } });
}

pub fn getItemHandler(ctx: *zest.Context) !void {
    if (!isAuthenticated(ctx)) return unauthorized(ctx);
    const id = ctx.paramInt("id", u32) orelse return notFound(ctx);
    const item = state().getItem(id) orelse return notFound(ctx);
    try ctx.jsonStatus(zest.Status.ok, .{ .data = .{ .id = item.id, .title = item.title, .content = item.content } });
}

pub fn updateItemHandler(ctx: *zest.Context) !void {
    if (!isAuthenticated(ctx)) return unauthorized(ctx);
    const id = ctx.paramInt("id", u32) orelse return notFound(ctx);
    const item = state().getItem(id) orelse return notFound(ctx);
    const body = ctx.bodyText() orelse return validationError(ctx, "body required");

    var parsed = try std.json.parseFromSlice(UpdateItemPayload, ctx.allocator, body, .{});
    defer parsed.deinit();

    if (parsed.value.title) |title| {
        ctx.allocator.free(item.title);
        item.title = try ctx.allocator.dupe(u8, title);
    }
    if (parsed.value.content) |content| {
        ctx.allocator.free(item.content);
        item.content = try ctx.allocator.dupe(u8, content);
    }

    try ctx.jsonStatus(zest.Status.ok, .{ .data = .{ .id = item.id, .title = item.title, .content = item.content } });
}

pub fn deleteItemHandler(ctx: *zest.Context) !void {
    if (!isAuthenticated(ctx)) return unauthorized(ctx);
    const id = ctx.paramInt("id", u32) orelse return notFound(ctx);
    const item = state().getItem(id) orelse return notFound(ctx);
    item.deleted = true;
    try ctx.jsonStatus(zest.Status.ok, .{ .data = .{ .id = item.id, .deleted = true } });
}

pub fn echoHandler(ctx: *zest.Context) !void {
    if (!isAuthenticated(ctx)) return unauthorized(ctx);
    const body = ctx.bodyText() orelse "";
    const authorization = ctx.header("Authorization") orelse "";
    try ctx.jsonStatus(zest.Status.ok, .{ .data = .{ .authorization = authorization, .body = body } });
}

pub fn redirectHandler(ctx: *zest.Context) !void {
    try ctx.redirectStatus("/redirect-target", zest.Status.found);
}

pub fn redirectTargetHandler(ctx: *zest.Context) !void {
    try ctx.jsonStatus(zest.Status.ok, .{ .data = .{ .target = true } });
}

fn isAuthenticated(ctx: *zest.Context) bool {
    if (!state().logged_in) return false;
    const cookie = ctx.header("Cookie") orelse return false;
    return std.mem.indexOf(u8, cookie, "zest_session=active") != null;
}

fn unauthorized(ctx: *zest.Context) !void {
    try ctx.jsonStatus(zest.Status.unauthorized, .{ .@"error" = .{ .code = "unauthenticated", .message = "Authentication required." } });
}

fn notFound(ctx: *zest.Context) !void {
    try ctx.jsonStatus(zest.Status.not_found, .{ .@"error" = .{ .code = "not_found", .message = "Item not found." } });
}

fn validationError(ctx: *zest.Context, message: []const u8) !void {
    try ctx.jsonStatus(zest.Status.unprocessable_entity, .{ .@"error" = .{ .code = "validation_error", .message = message } });
}
