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
        self.logEvent("http_request", req, null, null, self.config.fields.len);
    }

    pub fn logResponse(self: *LoggingMiddleware, req: RequestContext, resp: ResponseContext, start_time: i64) void {
        const duration = std.time.milliTimestamp() - start_time;
        self.logEvent("http_response", req, &resp, duration, self.config.fields.len + 1);
    }

    fn logEvent(
        self: *LoggingMiddleware,
        message: []const u8,
        req: RequestContext,
        resp: ?*const ResponseContext,
        duration: ?i64,
        field_capacity: usize,
    ) void {
        var fields = std.ArrayList(field.Field).initCapacity(self.allocator, field_capacity) catch |err| {
            std.log.warn("failed to allocate log fields for {s}: {}", .{ message, err });
            return;
        };
        defer fields.deinit();

        self.appendConfiguredFields(&fields, req, resp, duration);
        self.logger.log(Level.info, message, fields.items);
    }

    fn appendConfiguredFields(
        self: *LoggingMiddleware,
        fields: *std.ArrayList(field.Field),
        req: RequestContext,
        resp: ?*const ResponseContext,
        duration: ?i64,
    ) void {
        for (self.config.fields) |field_type| {
            switch (field_type) {
                .method => self.appendField(fields, field.Field.string("method", req.method)),
                .path => self.appendField(fields, field.Field.string("path", req.path)),
                .status => if (resp) |response| {
                    self.appendField(fields, field.Field.uint("status", response.status));
                },
                .duration => if (duration) |elapsed_ms| {
                    self.appendField(fields, field.Field.int("duration_ms", elapsed_ms));
                },
                .request_id => {
                    if (req.getHeader(self.config.request_id_header)) |rid| {
                        self.appendField(fields, field.Field.string("request_id", rid));
                    }
                },
                .remote_addr => self.appendField(fields, field.Field.string("remote_addr", req.remote_addr)),
                .user_agent => {
                    if (req.getHeader("User-Agent")) |ua| {
                        self.appendField(fields, field.Field.string("user_agent", ua));
                    }
                },
                .content_length => {
                    if (req.getHeader("Content-Length")) |cl| {
                        self.appendField(fields, field.Field.string("content_length", cl));
                    }
                },
                .content_type => {
                    if (req.getHeader("Content-Type")) |ct| {
                        self.appendField(fields, field.Field.string("content_type", ct));
                    }
                },
            }
        }
    }

    fn appendField(_: *LoggingMiddleware, fields: *std.ArrayList(field.Field), value: field.Field) void {
        fields.append(value) catch |err| {
            std.log.warn("failed to append log field: {}", .{err});
        };
    }

    pub fn execute(self: *LoggingMiddleware, req: RequestContext, handler_fn: *const fn (RequestContext) anyerror!ResponseContext) anyerror!ResponseContext {
        const start_time = std.time.milliTimestamp();

        self.logRequest(req);

        const resp = try handler_fn(req);

        self.logResponse(req, resp, start_time);

        return resp;
    }
};
