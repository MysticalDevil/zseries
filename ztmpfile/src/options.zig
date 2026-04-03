pub const CreateOptions = struct {
    prefix: []const u8 = "ztmpfile-",
    suffix: []const u8 = "",
    rand_len: usize = 12,
    max_attempts: usize = 32,
    parent_dir: ?[]const u8 = null,
};
