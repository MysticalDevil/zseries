const std = @import("std");
const model = @import("model.zig");
const storage = @import("storage.zig");
const totp = @import("totp.zig");
const import_export = @import("import_export.zig");

pub const CommandError = error{ InvalidArgs, EntryNotFound, VaultAlreadyExists, VaultMissing };

pub fn run(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    if (args.len < 2) {
        try printHelp();
        return;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printHelp();
        return;
    }
    if (std.mem.eql(u8, command, "init")) return runInit(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "add")) return runAdd(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "list")) return runList(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "search")) return runSearch(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "code")) return runCode(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "remove")) return runRemove(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "export")) return runExport(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "import")) return runImport(allocator, io, env, args[2..]);
    return error.InvalidArgs;
}

fn printHelp() !void {
    std.debug.print(
        "ztotp - local-first encrypted TOTP manager\n" ++
            "Commands:\n" ++
            "  init [--password PASS]\n" ++
            "  add --issuer ISSUER --account ACCOUNT --secret SECRET [--digits 6] [--period 30] [--algorithm SHA1] [--tag TAG]... [--note TEXT] [--password PASS]\n" ++
            "  list [--password PASS]\n" ++
            "  search [--issuer NAME] [--account NAME] [--tag TAG] [--password PASS]\n" ++
            "  code (--id ID | QUERY) [--password PASS]\n" ++
            "  remove --id ID [--password PASS]\n" ++
            "  import --from (otpauth|json|csv) --file PATH [--password PASS]\n" ++
            "  export --to (otpauth|json|csv) --file PATH [--password PASS]\n" ++
            "Password sources: --password, ZTOTP_PASSWORD, stdin prompt\n",
        .{},
    );
}

fn argValue(args: []const []const u8, name: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], name)) {
            if (i + 1 < args.len) return args[i + 1];
            return null;
        }
    }
    return null;
}

fn collectRepeatedArgs(allocator: std.mem.Allocator, args: []const []const u8, name: []const u8) ![]const []const u8 {
    var list = std.ArrayList([]const u8).empty;
    defer list.deinit(allocator);
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], name) and i + 1 < args.len) {
            try list.append(allocator, try allocator.dupe(u8, args[i + 1]));
        }
    }
    return list.toOwnedSlice(allocator);
}

fn promptLine(allocator: std.mem.Allocator, io: std.Io, prompt: []const u8) ![]const u8 {
    std.debug.print("{s}", .{prompt});
    var buffer: [1024]u8 = undefined;
    var reader = std.Io.File.stdin().reader(io, &buffer);
    const line = (try reader.interface.takeDelimiter('\n')) orelse return error.EndOfStream;
    return try allocator.dupe(u8, std.mem.trim(u8, line, "\r"));
}

fn passwordForCommand(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) ![]const u8 {
    if (argValue(args, "--password")) |password| return try allocator.dupe(u8, password);
    if (env.get("ZTOTP_PASSWORD")) |password| return try allocator.dupe(u8, password);
    return promptLine(allocator, io, "Master password: ");
}

fn dataDirForCommand(allocator: std.mem.Allocator, env: *const std.process.Environ.Map) ![]const u8 {
    if (env.get("XDG_DATA_HOME")) |value| return try allocator.dupe(u8, value);
    const home = env.get("HOME") orelse return error.MissingHome;
    return try std.fs.path.join(allocator, &.{ home, ".local", "share" });
}

fn nowTimestamp(io: std.Io) i64 {
    return std.Io.Clock.real.now(io).toSeconds();
}

fn loadEntries(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !struct { password: []const u8, data_dir: []const u8, vault: storage.LoadedVault } {
    const data_dir = try dataDirForCommand(allocator, env);
    errdefer allocator.free(data_dir);
    if (!try storage.vaultExists(allocator, io, data_dir)) return error.VaultMissing;
    const password = try passwordForCommand(allocator, io, env, args);
    const vault = try storage.loadVault(allocator, io, data_dir, password);
    return .{ .password = password, .data_dir = data_dir, .vault = vault };
}

fn saveEntries(allocator: std.mem.Allocator, io: std.Io, data_dir: []const u8, password: []const u8, entries: []const model.Entry) !void {
    const path = try storage.saveVault(allocator, io, data_dir, password, .{ .entries = entries });
    allocator.free(path);
}

fn runInit(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    const data_dir = try dataDirForCommand(allocator, env);
    defer allocator.free(data_dir);
    if (try storage.vaultExists(allocator, io, data_dir)) return error.VaultAlreadyExists;
    const password = try passwordForCommand(allocator, io, env, args);
    defer allocator.free(password);
    const path = try storage.saveVault(allocator, io, data_dir, password, .{ .entries = &.{} });
    defer allocator.free(path);
    std.debug.print("Initialized vault at {s}\n", .{path});
}

fn runAdd(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    var state = try loadEntries(allocator, io, env, args);
    defer allocator.free(state.password);
    defer allocator.free(state.data_dir);
    defer state.vault.deinit();

    const issuer = argValue(args, "--issuer") orelse return error.InvalidArgs;
    const account = argValue(args, "--account") orelse return error.InvalidArgs;
    const secret = argValue(args, "--secret") orelse return error.InvalidArgs;
    const digits = if (argValue(args, "--digits")) |value| try std.fmt.parseInt(u8, value, 10) else 6;
    const period = if (argValue(args, "--period")) |value| try std.fmt.parseInt(u32, value, 10) else 30;
    const algorithm = if (argValue(args, "--algorithm")) |value| model.Algorithm.fromString(value) orelse return error.InvalidArgs else .sha1;
    const tags = try collectRepeatedArgs(allocator, args, "--tag");
    const note = argValue(args, "--note");
    const ts = nowTimestamp(io);

    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    try entries.appendSlice(allocator, state.vault.payload.entries);
    try entries.append(allocator, .{
        .id = try std.fmt.allocPrint(allocator, "entry-{d}", .{ts}),
        .issuer = try allocator.dupe(u8, issuer),
        .account_name = try allocator.dupe(u8, account),
        .secret = try allocator.dupe(u8, secret),
        .digits = digits,
        .period = period,
        .algorithm = algorithm,
        .tags = tags,
        .note = if (note) |value| try allocator.dupe(u8, value) else null,
        .created_at = ts,
        .updated_at = ts,
    });

    try saveEntries(allocator, io, state.data_dir, state.password, try entries.toOwnedSlice(allocator));
    std.debug.print("Added entry for {s}/{s}\n", .{ issuer, account });
}

fn printEntries(entries: []const model.Entry) void {
    for (entries) |entry| {
        std.debug.print("{s}\t{s}\t{s}\t{s}\n", .{ entry.id, entry.issuer, entry.account_name, entry.algorithm.asString() });
    }
}

fn runList(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    var state = try loadEntries(allocator, io, env, args);
    defer allocator.free(state.password);
    defer allocator.free(state.data_dir);
    defer state.vault.deinit();
    printEntries(state.vault.payload.entries);
}

fn matchEntry(entry: model.Entry, issuer: ?[]const u8, account: ?[]const u8, tag: ?[]const u8) bool {
    if (issuer) |value| {
        if (std.mem.indexOf(u8, entry.issuer, value) == null) return false;
    }
    if (account) |value| {
        if (std.mem.indexOf(u8, entry.account_name, value) == null) return false;
    }
    if (tag) |value| {
        for (entry.tags) |current| {
            if (std.mem.eql(u8, current, value)) return true;
        }
        return false;
    }
    return true;
}

fn runSearch(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    var state = try loadEntries(allocator, io, env, args);
    defer allocator.free(state.password);
    defer allocator.free(state.data_dir);
    defer state.vault.deinit();

    const issuer = argValue(args, "--issuer");
    const account = argValue(args, "--account");
    const tag = argValue(args, "--tag");

    for (state.vault.payload.entries) |entry| {
        if (matchEntry(entry, issuer, account, tag)) {
            std.debug.print("{s}\t{s}\t{s}\n", .{ entry.id, entry.issuer, entry.account_name });
        }
    }
}

fn resolveEntry(entries: []const model.Entry, query: []const u8) ?model.Entry {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.id, query)) return entry;
        if (std.mem.indexOf(u8, entry.issuer, query) != null) return entry;
        if (std.mem.indexOf(u8, entry.account_name, query) != null) return entry;
    }
    return null;
}

fn runCode(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    var state = try loadEntries(allocator, io, env, args);
    defer allocator.free(state.password);
    defer allocator.free(state.data_dir);
    defer state.vault.deinit();

    const query = if (argValue(args, "--id")) |id| id else if (args.len > 0) args[0] else return error.InvalidArgs;
    const entry = resolveEntry(state.vault.payload.entries, query) orelse return error.EntryNotFound;
    const code = try totp.generate(allocator, entry, nowTimestamp(io));
    std.debug.print("{s}\t{s}\t{s}\t{s}\t{d}s\n", .{ entry.id, entry.issuer, entry.account_name, code.code[8 - code.len ..], code.remaining_seconds });
}

fn runRemove(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    var state = try loadEntries(allocator, io, env, args);
    defer allocator.free(state.password);
    defer allocator.free(state.data_dir);
    defer state.vault.deinit();

    const id = argValue(args, "--id") orelse return error.InvalidArgs;
    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    var removed = false;
    for (state.vault.payload.entries) |entry| {
        if (std.mem.eql(u8, entry.id, id)) {
            removed = true;
            continue;
        }
        try entries.append(allocator, entry);
    }
    if (!removed) return error.EntryNotFound;
    try saveEntries(allocator, io, state.data_dir, state.password, try entries.toOwnedSlice(allocator));
    std.debug.print("Removed {s}\n", .{id});
}

fn loadFileAlloc(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(std.math.maxInt(usize)));
}

fn writeFile(io: std.Io, path: []const u8, bytes: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes });
}

fn runExport(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    var state = try loadEntries(allocator, io, env, args);
    defer allocator.free(state.password);
    defer allocator.free(state.data_dir);
    defer state.vault.deinit();
    const format = argValue(args, "--to") orelse return error.InvalidArgs;
    const path = argValue(args, "--file") orelse return error.InvalidArgs;

    const bytes = if (std.mem.eql(u8, format, "json"))
        try import_export.exportJson(allocator, state.vault.payload.entries, nowTimestamp(io))
    else if (std.mem.eql(u8, format, "csv"))
        try import_export.exportCsv(allocator, state.vault.payload.entries)
    else if (std.mem.eql(u8, format, "otpauth"))
        try import_export.exportOtpAuth(allocator, state.vault.payload.entries)
    else
        return error.InvalidArgs;
    defer allocator.free(bytes);

    try writeFile(io, path, bytes);
    std.debug.print("Exported to {s}\n", .{path});
}

fn runImport(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    var state = try loadEntries(allocator, io, env, args);
    defer allocator.free(state.password);
    defer allocator.free(state.data_dir);
    defer state.vault.deinit();

    const format = argValue(args, "--from") orelse return error.InvalidArgs;
    const path = argValue(args, "--file") orelse return error.InvalidArgs;
    const bytes = try loadFileAlloc(allocator, io, path);
    defer allocator.free(bytes);
    const imported = if (std.mem.eql(u8, format, "json"))
        try import_export.importJson(allocator, bytes)
    else if (std.mem.eql(u8, format, "csv"))
        try import_export.importCsv(allocator, bytes)
    else if (std.mem.eql(u8, format, "otpauth"))
        try import_export.importOtpAuth(allocator, bytes, nowTimestamp(io))
    else
        return error.InvalidArgs;

    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    try entries.appendSlice(allocator, state.vault.payload.entries);
    try entries.appendSlice(allocator, imported);
    try saveEntries(allocator, io, state.data_dir, state.password, try entries.toOwnedSlice(allocator));
    std.debug.print("Imported {d} entries from {s}\n", .{ imported.len, path });
}
