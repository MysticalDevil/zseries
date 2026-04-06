const std = @import("std");

pub const LogField = enum {
    method,
    path,
    status,
    duration,
    request_id,
    user_agent,
    remote_addr,
    content_length,
    content_type,
};

pub const MiddlewareConfig = struct {
    fields: []const LogField = &[_]LogField{
        .method,
        .path,
        .status,
        .duration,
    },
    request_id_header: []const u8 = "X-Request-Id",
    json_format: bool = true,
    log_request_body: bool = false,
    log_response_body: bool = false,
    max_body_size: usize = 1024,
};

pub const default_config = MiddlewareConfig{};
