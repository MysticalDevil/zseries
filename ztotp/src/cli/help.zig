const std = @import("std");
const zcli = @import("zcli");
const color = zcli.color;
const helpfmt = zcli.helpfmt;

pub const Section = struct {
    name: []const u8,
    summary: []const u8,
};

const commands = [_]Section{
    .{ .name = "init", .summary = "Create a new encrypted local vault" },
    .{ .name = "add", .summary = "Add a TOTP entry" },
    .{ .name = "list", .summary = "List stored entries" },
    .{ .name = "search", .summary = "Filter entries by issuer, account, or tag" },
    .{ .name = "code", .summary = "Show the current TOTP code for one entry" },
    .{ .name = "tui", .summary = "Open the searchable OTP dashboard" },
    .{ .name = "update", .summary = "Update an existing entry" },
    .{ .name = "remove", .summary = "Remove an entry by id" },
    .{ .name = "import", .summary = "Import entries from backup formats" },
    .{ .name = "export", .summary = "Export entries for backup or migration" },
};

pub fn isKnownCommand(name: []const u8) bool {
    for (commands) |command| {
        if (std.mem.eql(u8, command.name, name)) return true;
    }
    return false;
}

fn writeHeader(writer: *std.Io.Writer, use_color: bool, title: []const u8, subtitle: []const u8) !void {
    try helpfmt.writeHeader(writer, use_color, title, subtitle);
}

fn writeHeading(writer: *std.Io.Writer, use_color: bool, name: []const u8) !void {
    try helpfmt.writeHeading(writer, use_color, name);
}

fn writeCommandRow(writer: *std.Io.Writer, use_color: bool, name: []const u8, summary: []const u8) !void {
    try helpfmt.writeCommandRow(writer, use_color, name, summary);
}

fn writeBullet(writer: *std.Io.Writer, use_color: bool, label: []const u8, value: []const u8) !void {
    try helpfmt.writeBullet(writer, use_color, label, value);
}

fn writeExample(writer: *std.Io.Writer, use_color: bool, example: []const u8) !void {
    try helpfmt.writeExample(writer, use_color, example);
}

fn writeFormats(writer: *std.Io.Writer, use_color: bool) !void {
    try writeHeading(writer, use_color, "Formats");
    try writer.writeAll("  ");
    const formats = [_][]const u8{
        "otpauth",
        "json",
        "csv",
        "aegis",
        "aegis-encrypted",
        "authy",
        "2fas",
        "2fas-encrypted",
        "andotp",
        "andotp-encrypted",
        "andotp-encrypted-old",
        "bitwarden",
        "proton-authenticator",
        "ente-auth",
    };
    for (formats, 0..) |format, index| {
        if (index > 0) try writer.writeAll(", ");
        try color.writeStyled(writer, use_color, .value, format);
    }
    try writer.writeAll("\n\n");
}

fn renderGeneralHelpAlloc(allocator: std.mem.Allocator, use_color: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;

    try writeHeader(writer, use_color, "ztotp", "Local-first encrypted TOTP manager");

    try writeHeading(writer, use_color, "Usage");
    try writeExample(writer, use_color, "ztotp <command> [options]");
    try writeExample(writer, use_color, "ztotp help <command>");
    try writer.writeAll("\n");

    try writeHeading(writer, use_color, "Commands");
    for (commands) |command| {
        try writeCommandRow(writer, use_color, command.name, command.summary);
    }
    try writer.writeAll("\n");

    try writeFormats(writer, use_color);

    try writeHeading(writer, use_color, "Password");
    try writeBullet(writer, use_color, "--password <value>", "Provide the vault password explicitly");
    try writeBullet(writer, use_color, "ZTOTP_PASSWORD", "Read the password from the environment");
    try writeBullet(writer, use_color, "TTY prompt", "Fallback to a hidden password prompt when interactive");
    try writer.writeAll("\n");

    try writeHeading(writer, use_color, "Storage");
    try writeBullet(writer, use_color, "$XDG_DATA_HOME/ztotp/vault.bin", "Preferred vault location");
    try writeBullet(writer, use_color, "$HOME/.local/share/ztotp/vault.bin", "Fallback when XDG_DATA_HOME is unset");
    try writer.writeAll("\n");

    try writeHeading(writer, use_color, "Examples");
    try writeExample(writer, use_color, "ztotp init");
    try writeExample(writer, use_color, "ztotp add --issuer GitHub --account alice@example.com --secret JBSWY3DPEHPK3PXP --tag work");
    try writeExample(writer, use_color, "ztotp code GitHub");
    try writeExample(writer, use_color, "ztotp import --from aegis --file backup.json");
    try writeExample(writer, use_color, "ztotp export --to authy --file authy.json");
    try writer.writeAll("\n");

    try color.writeStyled(writer, use_color, .muted, "Run 'ztotp help <command>' for command-specific help.");
    try writer.writeAll("\n");

    return out.toOwnedSlice();
}

fn renderInitHelpAlloc(allocator: std.mem.Allocator, use_color: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writeHeader(writer, use_color, "ztotp init", "Create a new encrypted local vault");
    try writeHeading(writer, use_color, "Usage");
    try writeExample(writer, use_color, "ztotp init [--password <value>]");
    try writer.writeAll("\n");
    try writeHeading(writer, use_color, "Notes");
    try writeBullet(writer, use_color, "storage", "Uses the XDG data directory by default");
    try writeBullet(writer, use_color, "password", "Reads from --password, ZTOTP_PASSWORD, or hidden TTY prompt");
    try writer.writeAll("\n");
    try writeHeading(writer, use_color, "Examples");
    try writeExample(writer, use_color, "ztotp init");
    try writeExample(writer, use_color, "ztotp init --password secret");
    return out.toOwnedSlice();
}

fn renderAddHelpAlloc(allocator: std.mem.Allocator, use_color: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writeHeader(writer, use_color, "ztotp add", "Add a TOTP entry to the local vault");
    try writeHeading(writer, use_color, "Usage");
    try writeExample(writer, use_color, "ztotp add --issuer <name> --account <name> --secret <base32> [options]");
    try writer.writeAll("\n");
    try writeHeading(writer, use_color, "Options");
    try writeBullet(writer, use_color, "--issuer <name>", "Issuer or service name");
    try writeBullet(writer, use_color, "--account <name>", "Account, email, or username label");
    try writeBullet(writer, use_color, "--secret <base32>", "Base32-encoded TOTP secret");
    try writeBullet(writer, use_color, "--digits <n>", "Code length, default 6");
    try writeBullet(writer, use_color, "--period <n>", "Step size in seconds, default 30");
    try writeBullet(writer, use_color, "--algorithm <SHA1|SHA256|SHA512>", "Hash algorithm, default SHA1");
    try writeBullet(writer, use_color, "--tag <name>", "Repeatable tag for grouping and search");
    try writeBullet(writer, use_color, "--note <text>", "Optional free-form note");
    try writer.writeAll("\n");
    try writeHeading(writer, use_color, "Examples");
    try writeExample(writer, use_color, "ztotp add --issuer GitHub --account alice@example.com --secret JBSWY3DPEHPK3PXP");
    try writeExample(writer, use_color, "ztotp add --issuer OpenAI --account team@example.com --secret AAAA --algorithm SHA256 --digits 8");
    return out.toOwnedSlice();
}

fn renderListHelpAlloc(allocator: std.mem.Allocator, use_color: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writeHeader(writer, use_color, "ztotp list", "List stored entries, including readonly imported kinds");
    try writeHeading(writer, use_color, "Usage");
    try writeExample(writer, use_color, "ztotp list");
    return out.toOwnedSlice();
}

fn renderSearchHelpAlloc(allocator: std.mem.Allocator, use_color: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writeHeader(writer, use_color, "ztotp search", "Filter entries by issuer, account, or tag");
    try writeHeading(writer, use_color, "Usage");
    try writeExample(writer, use_color, "ztotp search [--issuer <text>] [--account <text>] [--tag <name>]");
    try writer.writeAll("\n");
    try writeHeading(writer, use_color, "Examples");
    try writeExample(writer, use_color, "ztotp search --issuer GitHub");
    try writeExample(writer, use_color, "ztotp search --tag work");
    return out.toOwnedSlice();
}

fn renderCodeHelpAlloc(allocator: std.mem.Allocator, use_color: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writeHeader(writer, use_color, "ztotp code", "Show the current TOTP code for one entry");
    try writeHeading(writer, use_color, "Usage");
    try writeExample(writer, use_color, "ztotp code <query>");
    try writeExample(writer, use_color, "ztotp code --id <entry-id>");
    try writer.writeAll("\n");
    try writeHeading(writer, use_color, "Notes");
    try writeBullet(writer, use_color, "query", "Matches id, issuer, or account text");
    try writeBullet(writer, use_color, "output", "Prints id, issuer, account, code, and remaining seconds");
    try writeBullet(writer, use_color, "readonly kinds", "HOTP, Steam, and unknown entries are stored but rejected here");
    try writer.writeAll("\n");
    try writeHeading(writer, use_color, "Examples");
    try writeExample(writer, use_color, "ztotp code GitHub");
    try writeExample(writer, use_color, "ztotp code --id 60849c8d-c5d3-4182-8a6b-5c80a614e941");
    return out.toOwnedSlice();
}

fn renderTuiHelpAlloc(allocator: std.mem.Allocator, use_color: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writeHeader(writer, use_color, "ztotp tui", "Open a searchable dashboard for TOTP and readonly imported entries");
    try writeHeading(writer, use_color, "Usage");
    try writeExample(writer, use_color, "ztotp tui");
    try writer.writeAll("\n");
    try writeHeading(writer, use_color, "Keys");
    try writeBullet(writer, use_color, "type to search", "Filter by issuer, account, source, or kind");
    try writeBullet(writer, use_color, "Backspace", "Delete the last search character");
    try writeBullet(writer, use_color, "Esc", "Clear the search query");
    try writeBullet(writer, use_color, "q", "Quit the dashboard");
    try writer.writeAll("\n");
    try writeHeading(writer, use_color, "Layout");
    try writeBullet(writer, use_color, "TOTP", "Shows current codes and countdown cards");
    try writeBullet(writer, use_color, "Readonly", "Shows imported HOTP, Steam, and unknown entries in a separate section");
    return out.toOwnedSlice();
}

fn renderUpdateHelpAlloc(allocator: std.mem.Allocator, use_color: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writeHeader(writer, use_color, "ztotp update", "Update an existing entry");
    try writeHeading(writer, use_color, "Usage");
    try writeExample(writer, use_color, "ztotp update --id <entry-id> [field updates]");
    try writeExample(writer, use_color, "ztotp update --query <text> [field updates]");
    try writer.writeAll("\n");
    try writeHeading(writer, use_color, "How selection works");
    try writeBullet(writer, use_color, "--id", "Update a single entry by exact id");
    try writeBullet(writer, use_color, "--query", "Search by id, issuer, or account text");
    try writeBullet(writer, use_color, "multiple matches", "Shows an interactive picker when more than one entry matches");
    try writer.writeAll("\n");
    try writeHeading(writer, use_color, "Fields");
    try writeBullet(writer, use_color, "--issuer <name>", "Replace the issuer name");
    try writeBullet(writer, use_color, "--account <name>", "Replace the account label");
    try writeBullet(writer, use_color, "--secret <base32>", "Replace the Base32 secret");
    try writeBullet(writer, use_color, "--digits <n>", "Replace code length");
    try writeBullet(writer, use_color, "--period <n>", "Replace step size in seconds");
    try writeBullet(writer, use_color, "--algorithm <SHA1|SHA256|SHA512>", "Replace the hash algorithm");
    try writeBullet(writer, use_color, "--set-tags a,b,c", "Replace tags with a comma-separated list");
    try writeBullet(writer, use_color, "--clear-tags", "Remove all tags");
    try writeBullet(writer, use_color, "--note <text>", "Replace the note text");
    try writeBullet(writer, use_color, "readonly entries", "Imported non-TOTP entries are currently read-only");
    try writer.writeAll("\n");
    try writeHeading(writer, use_color, "Examples");
    try writeExample(writer, use_color, "ztotp update --id entry-1700000000 --issuer GitHub --note primary");
    try writeExample(writer, use_color, "ztotp update --query GitHub --set-tags work,prod");
    return out.toOwnedSlice();
}

fn renderRemoveHelpAlloc(allocator: std.mem.Allocator, use_color: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writeHeader(writer, use_color, "ztotp remove", "Remove an entry from the vault");
    try writeHeading(writer, use_color, "Usage");
    try writeExample(writer, use_color, "ztotp remove --id <entry-id>");
    return out.toOwnedSlice();
}

fn renderImportHelpAlloc(allocator: std.mem.Allocator, use_color: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writeHeader(writer, use_color, "ztotp import", "Import entries from another app or backup file");
    try writeHeading(writer, use_color, "Usage");
    try writeExample(writer, use_color, "ztotp import --from <format> --file <path>");
    try writer.writeAll("\n");
    try writeFormats(writer, use_color);
    try writeHeading(writer, use_color, "Notes");
    try writeBullet(writer, use_color, "aegis-encrypted", "Uses the current vault password to decrypt the backup");
    try writeBullet(writer, use_color, "authy", "Imports Authy authy-export compatible backup JSON");
    try writeBullet(writer, use_color, "otpauth", "Imports TOTP, HOTP, and Steam entries; non-TOTP entries become readonly");
    try writeBullet(writer, use_color, "2fas / andotp", "Support plain and encrypted exports; non-TOTP entries are imported readonly");
    try writeBullet(writer, use_color, "bitwarden / proton / ente", "Extract OTP entries from supported export files");
    try writer.writeAll("\n");
    try writeHeading(writer, use_color, "Examples");
    try writeExample(writer, use_color, "ztotp import --from aegis --file aegis_plain.json");
    try writeExample(writer, use_color, "ztotp import --from aegis-encrypted --file aegis_encrypted.json");
    try writeExample(writer, use_color, "ztotp import --from 2fas-encrypted --file twofas.2fas");
    try writeExample(writer, use_color, "ztotp import --from andotp-encrypted --file andotp.bin");
    try writeExample(writer, use_color, "ztotp import --from authy --file authy.json");
    try writeExample(writer, use_color, "ztotp import --from bitwarden --file bitwarden.json");
    return out.toOwnedSlice();
}

fn renderExportHelpAlloc(allocator: std.mem.Allocator, use_color: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writeHeader(writer, use_color, "ztotp export", "Export entries for backup or migration");
    try writeHeading(writer, use_color, "Usage");
    try writeExample(writer, use_color, "ztotp export --to <format> --file <path>");
    try writer.writeAll("\n");
    try writeFormats(writer, use_color);
    try writeHeading(writer, use_color, "Notes");
    try writeBullet(writer, use_color, "aegis-encrypted", "Encrypts the export with the current vault password");
    try writeBullet(writer, use_color, "authy", "Writes an authy-export compatible backup JSON");
    try writeBullet(writer, use_color, "json", "Best format for full ztotp backups");
    try writer.writeAll("\n");
    try writeHeading(writer, use_color, "Examples");
    try writeExample(writer, use_color, "ztotp export --to json --file backup.json");
    try writeExample(writer, use_color, "ztotp export --to aegis-encrypted --file aegis.json");
    try writeExample(writer, use_color, "ztotp export --to otpauth --file otpauth.txt");
    return out.toOwnedSlice();
}

pub fn renderHelpAlloc(allocator: std.mem.Allocator, use_color: bool, command: ?[]const u8) ![]u8 {
    if (command == null) return renderGeneralHelpAlloc(allocator, use_color);
    const value = command.?;
    if (std.mem.eql(u8, value, "init")) return renderInitHelpAlloc(allocator, use_color);
    if (std.mem.eql(u8, value, "add")) return renderAddHelpAlloc(allocator, use_color);
    if (std.mem.eql(u8, value, "list")) return renderListHelpAlloc(allocator, use_color);
    if (std.mem.eql(u8, value, "search")) return renderSearchHelpAlloc(allocator, use_color);
    if (std.mem.eql(u8, value, "code")) return renderCodeHelpAlloc(allocator, use_color);
    if (std.mem.eql(u8, value, "tui")) return renderTuiHelpAlloc(allocator, use_color);
    if (std.mem.eql(u8, value, "update")) return renderUpdateHelpAlloc(allocator, use_color);
    if (std.mem.eql(u8, value, "remove")) return renderRemoveHelpAlloc(allocator, use_color);
    if (std.mem.eql(u8, value, "import")) return renderImportHelpAlloc(allocator, use_color);
    if (std.mem.eql(u8, value, "export")) return renderExportHelpAlloc(allocator, use_color);
    return error.UnknownCommand;
}

test "renders general help with command list" {
    const testing = std.testing;
    const text = try renderHelpAlloc(testing.allocator, false, null);
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "Commands") != null);
    try testing.expect(std.mem.indexOf(u8, text, "ztotp help <command>") != null);
    try testing.expect(std.mem.indexOf(u8, text, "aegis-encrypted") != null);
}

test "renders import help with examples" {
    const testing = std.testing;
    const text = try renderHelpAlloc(testing.allocator, false, "import");
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "Import entries from another app or backup file") != null);
    try testing.expect(std.mem.indexOf(u8, text, "ztotp import --from authy --file authy.json") != null);
}
