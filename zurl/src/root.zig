const std = @import("std");

pub const httpfile = @import("httpfile/root.zig");

test {
    std.testing.refAllDecls(@import("integration_test.zig"));
}
