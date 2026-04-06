const std = @import("std");
const Logger = @import("logger.zig").Logger;
const Level = @import("level.zig").Level;
const config_mod = @import("middleware/config.zig");
const MiddlewareConfig = config_mod.MiddlewareConfig;
const LogField = config_mod.LogField;
const field = @import("field.zig");

pub const RequestContext = struct {
    method: []const u8,
    path: []const u8,
    headers: std.StringHashMap([]const u8),
    remote_addr: []const u8,
    body: ?[]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *RequestContext) void {
        self.headers.deinit();
        if (self.body) |body| {
            self.allocator.free(body);
        }
    }

    pub fn getHeader(self: *const RequestContext, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }
};

pub const ResponseContext = struct {
    status: u16,
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ResponseContext) void {
        self.headers.deinit();
        if (self.body) |body| {
            self.allocator.free(body);
        }
    }
};

pub const LoggingMiddleware = struct {
    logger: *Logger,
    config: MiddlewareConfig,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, logger: *Logger, config: MiddlewareConfig) LoggingMiddleware {
        return .{
            .allocator = allocator,
            .logger = logger,
            .config = config,
        };
    }

    pub fn logRequest(self: *LoggingMiddleware, req: RequestContext) void {
        var fields = std.ArrayList(field.Field).initCapacity(self.allocator, self.config.fields.len) catch return;
        defer fields.deinit();

        for (self.config.fields) |field_type| {
            switch (field_type) {
                .method => fields.append(field.Field.string("method", req.method)) catch continue,
                .path => fields.append(field.Field.string("path", req.path)) catch continue,
                .remote_addr => fields.append(field.Field.string("remote_addr", req.remote_addr)) catch continue,
                .user_agent => {
                    if (req.getHeader("User-Agent")) |ua| {
                        fields.append(field.Field.string("user_agent", ua)) catch continue;
                    }
                },
                else => {},
            }
        }

        self.logger.log(Level.info, "http_request", fields.items);
    }

    pub fn logResponse(self: *LoggingMiddleware, req: RequestContext, resp: ResponseContext, start_time: i64) void {
        const duration = std.time.milliTimestamp() - start_time;

        var fields = std.ArrayList(field.Field).initCapacity(self.allocator, self.config.fields.len + 1) catch return;
        defer fields.deinit();

        for (self.config.fields) |field_type| {
            switch (field_type) {
                .method => fields.append(field.Field.string("method", req.method)) catch continue,
                .path => fields.append(field.Field.string("path", req.path)) catch continue,
                .status => fields.append(field.Field.uint("status", resp.status)) catch continue,
                .duration => fields.append(field.Field.int("duration_ms", duration)) catch continue,
                .request_id => {
                    if (req.getHeader(self.config.request_id_header)) |rid| {
                        fields.append(field.Field.string("request_id", rid)) catch continue;
                    }
                },
                .remote_addr => fields.append(field.Field.string("remote_addr", req.remote_addr)) catch continue,
                .user_agent => {
                    if (req.getHeader("User-Agent")) |ua| {
                        fields.append(field.Field.string("user_agent", ua)) catch continue;
                    }
                },
                .content_length => {
                    if (req.getHeader("Content-Length")) |cl| {
                        fields.append(field.Field.string("content_length", cl)) catch continue;
                    }
                },
                .content_type => {
                    if (req.getHeader("Content-Type")) |ct| {
                        fields.append(field.Field.string("content_type", ct)) catch continue;
                    }
                },
            }
        }

        self.logger.log(Level.info, "http_response", fields.items);
    }

    pub fn execute(self: *LoggingMiddleware, req: RequestContext, handler_fn: *const fn (RequestContext) anyerror!ResponseContext) anyerror!ResponseContext {
        const start_time = std.time.milliTimestamp();

        self.logRequest(req);

        const resp = try handler_fn(req);

        self.logResponse(req, resp, start_time);

        return resp;
    }
};
