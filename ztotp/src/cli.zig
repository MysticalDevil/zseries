const std = @import("std");
const model = @import("model.zig");
const storage = @import("storage.zig");
const totp = @import("totp.zig");
const importers = @import("importers.zig");
const exporters = @import("exporters.zig");
const input = @import("input.zig");
const zargs = @import("zcli").args;
const color = @import("zcli").color;
const zlog = @import("zlog");
const help = @import("cli/help.zig");
const tui = @import("tui/root.zig");

pub const CommandError = error{ InvalidArgs, EntryNotFound, VaultAlreadyExists, VaultMissing };

pub fn run(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    if (args.len < 2) {
        try printHelp(allocator, env, null);
        return;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        if (args.len >= 3) {
            try printHelp(allocator, env, args[2]);
        } else {
            try printHelp(allocator, env, null);
        }
        return;
    }
    if (!help.isKnownCommand(command)) {
        std.debug.print("Unknown command: {s}\n", .{command});
        std.debug.print("Run 'ztotp help' for usage.\n", .{});
        return error.InvalidArgs;
    }
    if (hasArg(args[2..], "--help") or hasArg(args[2..], "-h")) {
        try printHelp(allocator, env, command);
        return;
    }
    if (std.mem.eql(u8, command, "init")) return runInit(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "add")) return runAdd(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "list")) return runList(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "search")) return runSearch(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "code")) return runCode(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "tui")) return runTui(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "update")) return runUpdate(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "remove")) return runRemove(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "export")) return runExport(allocator, io, env, args[2..]);
    if (std.mem.eql(u8, command, "import")) return runImport(allocator, io, env, args[2..]);
    return error.InvalidArgs;
}

fn printHelp(allocator: std.mem.Allocator, env: *const std.process.Environ.Map, command: ?[]const u8) !void {
    const text = help.renderHelpAlloc(allocator, color.enabled(env), command) catch |err| switch (err) {
        error.UnknownCommand => {
            std.debug.print("Unknown help topic: {s}\n", .{command orelse "<unknown>"});
            std.debug.print("Run 'ztotp help' for usage.\n", .{});
            return;
        },
        else => return err,
    };
    defer allocator.free(text);
    std.debug.print("{s}", .{text});
}

inline fn hasArg(args: []const []const u8, name: []const u8) bool {
    return zargs.hasFlag(args, name);
}

inline fn argValue(args: []const []const u8, name: []const u8) ?[]const u8 {
    return zargs.flagValue(args, name);
}

fn securityParamsForCommand(env: *const std.process.Environ.Map, args: []const []const u8) storage.SecurityParams {
    if (hasArg(args, "--quick-init")) return storage.quick_security;
    if (env.get("ZTOTP_LOW_SECURITY") != null) return storage.quick_security;
    return storage.default_security;
}

fn collectRepeatedArgs(allocator: std.mem.Allocator, args: []const []const u8, name: []const u8) ![]const []const u8 {
    return zargs.repeatedFlags(allocator, args, name);
}

fn passwordForCommand(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) ![]const u8 {
    if (argValue(args, "--password")) |password| return try allocator.dupe(u8, password);
    if (env.get("ZTOTP_PASSWORD")) |password| return try allocator.dupe(u8, password);
    return input.promptPassword(allocator, io, "Master password: ");
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

fn saveEntries(allocator: std.mem.Allocator, io: std.Io, data_dir: []const u8, password: []const u8, entries: []const model.Entry, params: storage.SecurityParams) !void {
    const path = try storage.saveVault(allocator, io, data_dir, password, .{ .entries = entries }, params);
    allocator.free(path);
}

fn saveEntriesWithVault(allocator: std.mem.Allocator, io: std.Io, data_dir: []const u8, password: []const u8, entries: []const model.Entry, vault: storage.LoadedVault) !void {
    return saveEntries(allocator, io, data_dir, password, entries, vault.params);
}

fn runInit(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    const data_dir = try dataDirForCommand(allocator, env);
    defer allocator.free(data_dir);
    if (try storage.vaultExists(allocator, io, data_dir)) return error.VaultAlreadyExists;
    const password = try passwordForCommand(allocator, io, env, args);
    defer allocator.free(password);
    const params = securityParamsForCommand(env, args);
    const path = try storage.saveVault(allocator, io, data_dir, password, .{ .entries = &.{} }, params);
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

    try saveEntriesWithVault(allocator, io, state.data_dir, state.password, try entries.toOwnedSlice(allocator), state.vault);
    std.debug.print("Added entry for {s}/{s}\n", .{ issuer, account });
}

fn printEntries(entries: []const model.Entry) void {
    for (entries) |entry| {
        std.debug.print(
            "{s:<24}  {s:<16}  {s:<24}  {s:<8}  {s:<8}{s}\n",
            .{
                entry.id,
                entry.issuer,
                entry.account_name,
                entry.kind.asString(),
                entry.algorithm.asString(),
                if (entry.isReadonly()) "  readonly" else "",
            },
        );
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

fn matchQuery(entry: model.Entry, query: ?[]const u8) bool {
    const value = query orelse return true;
    return std.mem.indexOf(u8, entry.id, value) != null or
        std.mem.indexOf(u8, entry.issuer, value) != null or
        std.mem.indexOf(u8, entry.account_name, value) != null;
}

fn collectMatchIndexes(allocator: std.mem.Allocator, entries: []const model.Entry, issuer: ?[]const u8, account: ?[]const u8, tag: ?[]const u8, query: ?[]const u8) ![]usize {
    var matches = std.ArrayList(usize).empty;
    defer matches.deinit(allocator);
    for (entries, 0..) |entry, idx| {
        if (!matchEntry(entry, issuer, account, tag)) continue;
        if (!matchQuery(entry, query)) continue;
        try matches.append(allocator, idx);
    }
    return matches.toOwnedSlice(allocator);
}

fn resolveInteractiveEntryIndex(allocator: std.mem.Allocator, io: std.Io, entries: []const model.Entry, args: []const []const u8) !usize {
    if (argValue(args, "--id")) |id| {
        for (entries, 0..) |entry, idx| if (std.mem.eql(u8, entry.id, id)) return idx;
        return error.EntryNotFound;
    }

    const query = argValue(args, "--query");
    const issuer = if (query == null) argValue(args, "--issuer") else null;
    const account = if (query == null) argValue(args, "--account") else null;
    const tag = argValue(args, "--tag");
    const matches = try collectMatchIndexes(allocator, entries, issuer, account, tag, query);
    defer allocator.free(matches);
    if (matches.len == 0) return error.EntryNotFound;
    if (matches.len == 1) return matches[0];

    for (matches, 0..) |match, index| {
        const entry = entries[match];
        std.debug.print("{d}. {s:<24}  {s:<16}  {s}\n", .{ index + 1, entry.id, entry.issuer, entry.account_name });
    }
    const picked = try input.chooseIndex(allocator, io, matches.len, "Select entry: ");
    return matches[picked];
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
            std.debug.print("{s:<24}  {s:<16}  {s}\n", .{ entry.id, entry.issuer, entry.account_name });
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
    if (entry.kind != .totp) {
        std.debug.print("Entry '{s}' is readonly: kind '{s}' is stored but code generation is not supported.\n", .{ entry.id, entry.kind.asString() });
        return error.InvalidArgs;
    }
    const code = try totp.generate(allocator, entry, nowTimestamp(io));
    std.debug.print("{s}\t{s}\t{s}\t{s}\t{d}s\n", .{ entry.id, entry.issuer, entry.account_name, code.code[8 - code.len ..], code.remaining_seconds });
}

fn runTui(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    const loaded = loadEntries(allocator, io, env, args) catch |err| {
        switch (err) {
            error.VaultMissing => {
                std.debug.print("No vault found. Run 'ztotp init' first.\n", .{});
                return;
            },
            else => return err,
        }
    };
    var state = loaded;
    defer allocator.free(state.password);
    defer allocator.free(state.data_dir);
    defer state.vault.deinit();
    var log_cfg = try zlog.config.fromEnv(allocator, env);
    defer if (log_cfg.file_path) |path| allocator.free(path);
    if (env.get("ZTOTP_TUI_LOG")) |value| {
        if (log_cfg.file_path) |path| allocator.free(path);
        log_cfg.file_path = try allocator.dupe(u8, value);
    }
    if (argValue(args, "--log-file")) |value| {
        if (log_cfg.file_path) |path| allocator.free(path);
        log_cfg.file_path = try allocator.dupe(u8, value);
    }
    if (log_cfg.file_path == null) {
        log_cfg.file_path = try allocator.dupe(u8, ".tmp-tui.log");
    }
    if (argValue(args, "--log-level")) |value| {
        log_cfg.level_value = zlog.Level.fromString(value) orelse .trace;
    } else if (env.get("ZLOG_LEVEL") == null) {
        log_cfg.level_value = .trace;
    }
    if (hasArg(args, "--log-stdout")) log_cfg.stdout_enabled = true;
    if (hasArg(args, "--log-stderr")) log_cfg.stderr_enabled = true;

    tui.run(allocator, io, state.vault.payload.entries, .{
        .log_path = log_cfg.file_path,
        .log_level = log_cfg.level_value,
        .log_stdout = log_cfg.stdout_enabled,
        .log_stderr = log_cfg.stderr_enabled,
    }) catch |err| switch (err) {
        error.NotATerminal => {
            std.debug.print("ztotp tui requires an interactive TTY.\n", .{});
            return;
        },
        else => return err,
    };
}

fn splitTagsAlloc(allocator: std.mem.Allocator, raw: []const u8) ![]const []const u8 {
    var list = std.ArrayList([]const u8).empty;
    defer list.deinit(allocator);
    var it = std.mem.splitScalar(u8, raw, ',');
    while (it.next()) |tag| {
        const trimmed = std.mem.trim(u8, tag, " ");
        if (trimmed.len == 0) continue;
        try list.append(allocator, try allocator.dupe(u8, trimmed));
    }
    return list.toOwnedSlice(allocator);
}

fn runUpdate(allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) !void {
    var state = try loadEntries(allocator, io, env, args);
    defer allocator.free(state.password);
    defer allocator.free(state.data_dir);
    defer state.vault.deinit();

    const idx = try resolveInteractiveEntryIndex(allocator, io, state.vault.payload.entries, args);
    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    try entries.appendSlice(allocator, state.vault.payload.entries);

    var entry = entries.items[idx];
    if (entry.isReadonly()) {
        std.debug.print("Entry '{s}' is readonly and cannot be updated.\n", .{entry.id});
        return error.InvalidArgs;
    }
    if (argValue(args, "--issuer")) |value| entry.issuer = try allocator.dupe(u8, value);
    if (argValue(args, "--account")) |value| entry.account_name = try allocator.dupe(u8, value);
    if (argValue(args, "--secret")) |value| entry.secret = try allocator.dupe(u8, value);
    if (argValue(args, "--digits")) |value| entry.digits = try std.fmt.parseInt(u8, value, 10);
    if (argValue(args, "--period")) |value| entry.period = try std.fmt.parseInt(u32, value, 10);
    if (argValue(args, "--algorithm")) |value| entry.algorithm = model.Algorithm.fromString(value) orelse return error.InvalidArgs;
    if (hasArg(args, "--clear-tags")) entry.tags = &.{};
    if (argValue(args, "--set-tags")) |value| entry.tags = try splitTagsAlloc(allocator, value);
    if (argValue(args, "--note")) |value| entry.note = try allocator.dupe(u8, value);
    entry.updated_at = nowTimestamp(io);
    entries.items[idx] = entry;

    try saveEntriesWithVault(allocator, io, state.data_dir, state.password, try entries.toOwnedSlice(allocator), state.vault);
    std.debug.print("Updated {s}\n", .{entry.id});
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
    try saveEntriesWithVault(allocator, io, state.data_dir, state.password, try entries.toOwnedSlice(allocator), state.vault);
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
        try exporters.json(allocator, state.vault.payload.entries, nowTimestamp(io))
    else if (std.mem.eql(u8, format, "csv"))
        try exporters.csv(allocator, state.vault.payload.entries)
    else if (std.mem.eql(u8, format, "otpauth"))
        try exporters.otpauth(allocator, state.vault.payload.entries)
    else if (std.mem.eql(u8, format, "authy-otpauth"))
        try exporters.otpauth(allocator, state.vault.payload.entries)
    else if (std.mem.eql(u8, format, "aegis"))
        try exporters.third_party.aegis_plain(allocator, io, state.vault.payload.entries)
    else if (std.mem.eql(u8, format, "aegis-encrypted"))
        try exporters.third_party.aegis_encrypted(allocator, io, state.vault.payload.entries, state.password)
    else if (std.mem.eql(u8, format, "authy"))
        try exporters.third_party.authy_backup(allocator, io, state.vault.payload.entries, state.password)
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
        try importers.json(allocator, bytes)
    else if (std.mem.eql(u8, format, "csv"))
        try importers.csv(allocator, bytes)
    else if (std.mem.eql(u8, format, "otpauth"))
        try importers.otpauth(allocator, bytes, nowTimestamp(io))
    else if (std.mem.eql(u8, format, "authy-otpauth"))
        try importers.otpauth(allocator, bytes, nowTimestamp(io))
    else if (std.mem.eql(u8, format, "aegis"))
        try importers.third_party.aegis_plain(allocator, bytes, nowTimestamp(io))
    else if (std.mem.eql(u8, format, "aegis-encrypted"))
        try importers.third_party.aegis_encrypted(allocator, bytes, state.password, nowTimestamp(io))
    else if (std.mem.eql(u8, format, "authy"))
        try importers.third_party.authy_backup(allocator, bytes, state.password, nowTimestamp(io))
    else if (std.mem.eql(u8, format, "2fas"))
        try importers.third_party.twofas_plain(allocator, bytes, nowTimestamp(io))
    else if (std.mem.eql(u8, format, "2fas-encrypted"))
        try importers.third_party.twofas_encrypted(allocator, bytes, state.password, nowTimestamp(io))
    else if (std.mem.eql(u8, format, "andotp"))
        try importers.third_party.andotp_plain(allocator, bytes, nowTimestamp(io))
    else if (std.mem.eql(u8, format, "andotp-encrypted"))
        try importers.third_party.andotp_encrypted(allocator, bytes, state.password, nowTimestamp(io))
    else if (std.mem.eql(u8, format, "andotp-encrypted-old"))
        try importers.third_party.andotp_encrypted_old(allocator, bytes, state.password, nowTimestamp(io))
    else if (std.mem.eql(u8, format, "bitwarden"))
        try importers.third_party.bitwarden(allocator, bytes, nowTimestamp(io))
    else if (std.mem.eql(u8, format, "proton-authenticator"))
        try importers.third_party.proton_authenticator(allocator, bytes, nowTimestamp(io))
    else if (std.mem.eql(u8, format, "ente-auth"))
        try importers.third_party.ente_auth(allocator, bytes, nowTimestamp(io))
    else
        return error.InvalidArgs;

    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    try entries.appendSlice(allocator, state.vault.payload.entries);
    try entries.appendSlice(allocator, imported);
    try saveEntriesWithVault(allocator, io, state.data_dir, state.password, try entries.toOwnedSlice(allocator), state.vault);
    var readonly_count: usize = 0;
    for (imported) |entry| {
        if (entry.isReadonly()) readonly_count += 1;
    }
    std.debug.print(
        "Imported {d} entries from {s} ({d} totp, {d} readonly)\n",
        .{ imported.len, path, imported.len - readonly_count, readonly_count },
    );
}
