const std = @import("std");
const opts = @import("options.zig");
const temp_dir = @import("temp_dir.zig");
const named_temp_file = @import("named_temp_file.zig");
const CreateOptions = opts.CreateOptions;
const TempDir = temp_dir.TempDir;
const NamedTempFile = named_temp_file.NamedTempFile;

pub const Builder = struct {
    options: CreateOptions = .{},

    pub fn init() Builder {
        return .{};
    }

    pub fn prefix(self: *Builder, value: []const u8) *Builder {
        self.options.prefix = value;
        return self;
    }

    pub fn suffix(self: *Builder, value: []const u8) *Builder {
        self.options.suffix = value;
        return self;
    }

    pub fn randLen(self: *Builder, value: usize) *Builder {
        self.options.rand_len = @max(value, 4);
        return self;
    }

    pub fn maxAttempts(self: *Builder, value: usize) *Builder {
        self.options.max_attempts = @max(value, 1);
        return self;
    }

    pub fn inDir(self: *Builder, path: []const u8) *Builder {
        self.options.parent_dir = path;
        return self;
    }

    pub fn tempDir(self: *Builder, allocator: std.mem.Allocator) !TempDir {
        return TempDir.create(allocator, self.options);
    }

    pub fn namedTempFile(self: *Builder, allocator: std.mem.Allocator) !NamedTempFile {
        return NamedTempFile.create(allocator, self.options);
    }
};

pub fn tempdir(allocator: std.mem.Allocator) !TempDir {
    var b = Builder.init();
    return b.tempDir(allocator);
}

pub fn tempdirIn(allocator: std.mem.Allocator, dir_path: []const u8) !TempDir {
    var builder = Builder.init();
    return builder.inDir(dir_path).tempDir(allocator);
}

pub fn tempfile(allocator: std.mem.Allocator) !NamedTempFile {
    var b = Builder.init();
    return b.namedTempFile(allocator);
}

pub fn tempfileIn(allocator: std.mem.Allocator, dir_path: []const u8) !NamedTempFile {
    var builder = Builder.init();
    return builder.inDir(dir_path).namedTempFile(allocator);
}
