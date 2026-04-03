pub const CreateOptions = struct {
    prefix: []const u8 = "ztmpfile-",
    suffix: []const u8 = "",
    rand_len: usize = 12,
    max_attempts: usize = 32,
    parent_dir: ?[]const u8 = null,
};

test "CreateOptions exposes stable defaults" {
    const testing = @import("std").testing;
    const options = CreateOptions{};

    try testing.expectEqualStrings("ztmpfile-", options.prefix);
    try testing.expectEqualStrings("", options.suffix);
    try testing.expectEqual(@as(usize, 12), options.rand_len);
    try testing.expectEqual(@as(usize, 32), options.max_attempts);
    try testing.expectEqual(@as(?[]const u8, null), options.parent_dir);
}
