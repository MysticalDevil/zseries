const std = @import("std");
const zest = @import("zest");
const httpfile = @import("root.zig").httpfile;
const test_server = @import("test_server.zig");

const ServeFuture = std.Io.Future(std.Io.Cancelable!void);

var next_test_port = std.atomic.Value(u16).init(18081);

const RunningServer = struct {
    allocator: std.mem.Allocator,
    threaded: std.Io.Threaded,
    app: *zest.App,
    future: ServeFuture,
    port: u16,

    fn stop(self: *RunningServer) void {
        const io = self.threaded.io();
        self.app.stop();
        self.future.cancel(io) catch |err| switch (err) {
            error.Canceled => return,
        };
        self.app.deinit();
        self.app.allocator.destroy(self.app);
        self.threaded.deinit();
        self.allocator.destroy(self);
    }
};

test "httpfile runner executes auth flow against real test server" {
    const testing = std.testing;
    const server = try startServer(testing.allocator);
    defer server.stop();
    try waitForHealth(testing.allocator, server.threaded.io(), server.port);

    const auth_file = try testDataPath(testing.allocator, &.{ "http", "auth.http" });
    defer testing.allocator.free(auth_file);

    var document = try httpfile.parseFile(testing.allocator, auth_file);
    defer document.deinit(testing.allocator);

    var external = std.StringHashMap([]const u8).init(testing.allocator);
    defer external.deinit();
    const base_url = try std.fmt.allocPrint(testing.allocator, "http://127.0.0.1:{d}", .{server.port});
    defer testing.allocator.free(base_url);
    try external.put("baseUrl", base_url);
    try external.put("username", "admin");
    try external.put("password", "admin123456");

    var env = std.process.Environ.Map.init(testing.allocator);
    defer env.deinit();

    const rendered = try httpfile.renderDocument(testing.allocator, &document, &external, &env);
    defer {
        for (rendered) |request| request.deinit(testing.allocator);
        testing.allocator.free(rendered);
    }

    var session = httpfile.runner.Session.init(testing.allocator, server.threaded.io());
    defer session.deinit();

    const expected = [_]std.http.Status{ .ok, .unauthorized, .unprocessable_entity, .ok, .ok, .unauthorized };
    for (rendered, expected) |*request, status| {
        var response = try session.execute(request);
        defer response.deinit(testing.allocator);
        try testing.expectEqual(status, response.status);
    }
}

test "httpfile renders nested variables env interpolation and file bodies" {
    const testing = std.testing;
    const server = try startServer(testing.allocator);
    defer server.stop();
    try waitForHealth(testing.allocator, server.threaded.io(), server.port);

    const template_file = try testDataPath(testing.allocator, &.{ "http", "template-vars.http" });
    defer testing.allocator.free(template_file);
    var template_doc = try httpfile.parseFile(testing.allocator, template_file);
    defer template_doc.deinit(testing.allocator);

    var external = std.StringHashMap([]const u8).init(testing.allocator);
    defer external.deinit();
    const host_and_port = try std.fmt.allocPrint(testing.allocator, "127.0.0.1:{d}", .{server.port});
    defer testing.allocator.free(host_and_port);
    try external.put("host_and_port", host_and_port);

    var env = std.process.Environ.Map.init(testing.allocator);
    defer env.deinit();
    try env.put("ZURL_TOKEN", "token-123");

    const request = httpfile.findRequestByName(&template_doc, "templated") orelse return error.TestUnexpectedResult;
    var rendered = try httpfile.renderRequest(testing.allocator, &template_doc, request, &external, &env);
    defer rendered.deinit(testing.allocator);
    const expected_target = try std.fmt.allocPrint(testing.allocator, "http://127.0.0.1:{d}/health", .{server.port});
    defer testing.allocator.free(expected_target);
    try testing.expectEqualStrings(expected_target, rendered.target);
    try testing.expectEqualStrings("token-123", rendered.headers[0].value);

    const body_file = try testDataPath(testing.allocator, &.{ "http", "body-file.http" });
    defer testing.allocator.free(body_file);
    var body_doc = try httpfile.parseFile(testing.allocator, body_file);
    defer body_doc.deinit(testing.allocator);

    var body_external = std.StringHashMap([]const u8).init(testing.allocator);
    defer body_external.deinit();
    const base_url = try std.fmt.allocPrint(testing.allocator, "http://127.0.0.1:{d}", .{server.port});
    defer testing.allocator.free(base_url);
    try body_external.put("baseUrl", base_url);
    try body_external.put("username", "admin");
    try body_external.put("password", "admin123456");

    var body_env = std.process.Environ.Map.init(testing.allocator);
    defer body_env.deinit();
    try body_env.put("ZURL_TOKEN", "token-xyz");

    const requests = try httpfile.renderDocument(testing.allocator, &body_doc, &body_external, &body_env);
    defer {
        for (requests) |request_item| request_item.deinit(testing.allocator);
        testing.allocator.free(requests);
    }

    var session = httpfile.runner.Session.init(testing.allocator, server.threaded.io());
    defer session.deinit();

    var login_response = try session.execute(&requests[0]);
    defer login_response.deinit(testing.allocator);
    try testing.expectEqual(std.http.Status.ok, login_response.status);

    var echo_response = try session.execute(&requests[1]);
    defer echo_response.deinit(testing.allocator);
    try testing.expectEqual(std.http.Status.ok, echo_response.status);
    try testing.expect(std.mem.indexOf(u8, echo_response.body, "Bearer token-xyz") != null);
    try testing.expect(std.mem.indexOf(u8, echo_response.body, "hello from file body") != null);
}

test "zurl run CLI executes auth and redirect flows" {
    const testing = std.testing;
    const server = try startServer(testing.allocator);
    defer server.stop();
    try waitForHealth(testing.allocator, server.threaded.io(), server.port);

    const auth_file = try testDataPath(testing.allocator, &.{ "http", "auth.http" });
    defer testing.allocator.free(auth_file);
    const base_url = try std.fmt.allocPrint(testing.allocator, "http://127.0.0.1:{d}", .{server.port});
    defer testing.allocator.free(base_url);

    const auth_var = try std.fmt.allocPrint(testing.allocator, "baseUrl={s}", .{base_url});
    defer testing.allocator.free(auth_var);
    var cli_threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer cli_threaded.deinit();

    const auth_result = try std.process.run(testing.allocator, cli_threaded.io(), .{
        .argv = &.{
            "./zig-out/bin/zurl", "run",    auth_file,
            "--var",              auth_var, "--var",
            "username=admin",     "--var",  "password=admin123456",
        },
        .cwd = .{ .path = "." },
    });
    defer testing.allocator.free(auth_result.stdout);
    defer testing.allocator.free(auth_result.stderr);
    try testing.expectEqual(@as(u8, 0), switch (auth_result.term) {
        .exited => |code| code,
        else => 255,
    });
    try testing.expect(std.mem.indexOf(u8, auth_result.stdout, "< 200 ok") != null);
    try testing.expect(std.mem.indexOf(u8, auth_result.stdout, "< 401 unauthorized") != null);

    const redirect_file = try testDataPath(testing.allocator, &.{ "http", "redirect.http" });
    defer testing.allocator.free(redirect_file);
    const redirect_var = try std.fmt.allocPrint(testing.allocator, "baseUrl={s}", .{base_url});
    defer testing.allocator.free(redirect_var);
    const redirect_result = try std.process.run(testing.allocator, cli_threaded.io(), .{
        .argv = &.{
            "./zig-out/bin/zurl", "run",        redirect_file,
            "--var",              redirect_var,
        },
        .cwd = .{ .path = "." },
    });
    defer testing.allocator.free(redirect_result.stdout);
    defer testing.allocator.free(redirect_result.stderr);
    try testing.expectEqual(@as(u8, 0), switch (redirect_result.term) {
        .exited => |code| code,
        else => 255,
    });
    try testing.expect(std.mem.indexOf(u8, redirect_result.stdout, "< 302 found") != null);
    try testing.expect(std.mem.indexOf(u8, redirect_result.stdout, "Location: /redirect-target") != null);
}

fn startServer(allocator: std.mem.Allocator) !*RunningServer {
    const server = try allocator.create(RunningServer);
    errdefer allocator.destroy(server);

    server.* = .{
        .allocator = allocator,
        .threaded = std.Io.Threaded.init(std.heap.page_allocator, .{}),
        .app = undefined,
        .future = undefined,
        .port = undefined,
    };
    errdefer server.threaded.deinit();

    const io = server.threaded.io();
    const port = try pickPort(io);
    server.port = port;

    const app = try allocator.create(zest.App);
    errdefer allocator.destroy(app);
    app.* = try zest.App.init(allocator, io);
    errdefer app.deinit();
    server.app = app;

    const health_builder = try app.get("/health", test_server.healthHandler);
    _ = health_builder;
    const login_builder = try app.post("/session/login", test_server.loginHandler);
    _ = login_builder;
    _ = try app.post("/session/logout", test_server.logoutHandler);
    _ = try app.get("/session/me", test_server.meHandler);
    _ = try app.post("/items", test_server.createItemHandler);
    _ = try app.get("/items", test_server.listItemsHandler);
    _ = try app.get("/items/:id", test_server.getItemHandler);
    _ = try app.patch("/items/:id", test_server.updateItemHandler);
    _ = try app.delete("/items/:id", test_server.deleteItemHandler);
    _ = try app.post("/echo", test_server.echoHandler);
    _ = try app.get("/redirect", test_server.redirectHandler);
    _ = try app.get("/redirect-target", test_server.redirectTargetHandler);

    test_server.resetState(allocator);

    server.future = std.Io.async(io, serveApp, .{ app, std.Io.net.IpAddress{ .ip4 = std.Io.net.Ip4Address.loopback(port) } });
    return server;
}

fn waitForHealth(allocator: std.mem.Allocator, io: std.Io, port: u16) !void {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/health", .{port});
    defer allocator.free(url);

    var attempts: usize = 0;
    while (attempts < 120) : (attempts += 1) {
        const result = client.fetch(.{ .location = .{ .url = url } }) catch {
            try std.Io.sleep(io, .fromMilliseconds(50), .awake);
            continue;
        };
        if (result.status == .ok) return;
        try std.Io.sleep(io, .fromMilliseconds(50), .awake);
    }
    return error.ServerStartTimedOut;
}

fn serveApp(app: *zest.App, address: std.Io.net.IpAddress) std.Io.Cancelable!void {
    app.listen(address) catch |err| {
        std.debug.panic("test server listen failed: {t}", .{err});
    };
}

fn pickPort(io: std.Io) !u16 {
    var attempts: usize = 0;
    while (attempts < 64) : (attempts += 1) {
        const candidate = next_test_port.fetchAdd(1, .monotonic);
        var address = std.Io.net.IpAddress{ .ip4 = std.Io.net.Ip4Address.loopback(candidate) };
        var server = std.Io.net.IpAddress.listen(&address, io, .{}) catch |err| switch (err) {
            error.AddressInUse => continue,
            else => |e| return e,
        };
        server.deinit(io);
        return candidate;
    }
    return error.NoAvailablePort;
}

fn testDataPath(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    var full_parts = std.ArrayList([]const u8).empty;
    defer full_parts.deinit(allocator);
    try full_parts.append(allocator, ".");
    try full_parts.append(allocator, "testdata");
    for (parts) |part| {
        try full_parts.append(allocator, part);
    }
    return std.fs.path.join(allocator, full_parts.items);
}
