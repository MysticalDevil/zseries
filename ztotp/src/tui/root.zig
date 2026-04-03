const std = @import("std");
const model = @import("../model.zig");
const ztui = @import("ztui");
const dashboard = ztui.widgets.dashboard;
const buffer = ztui.buffer;
const widgets = ztui.widgets;
const view = @import("view.zig");
const totp = @import("../totp.zig");
const zlog = @import("zlog");

const card_width = 36;
const card_height_totp = 8;
const card_height_readonly = 7;

pub const Config = struct {
    log_path: ?[]const u8 = null,
    log_level: zlog.Level = .trace,
    log_stdout: bool = false,
    log_stderr: bool = false,
};

pub fn run(allocator: std.mem.Allocator, io: std.Io, entries: []const model.Entry, config: Config) !void {
    var logger: ?zlog.Logger = null;
    if (config.log_path) |path| {
        var l = zlog.Logger.init(allocator, io, config.log_level);
        errdefer l.deinit();
        try l.addFileSink(path);
        if (config.log_stdout) try l.addStdoutSink();
        if (config.log_stderr) try l.addStderrSink();
        logger = l;
    }
    defer if (logger) |*l| l.deinit();

    const totp_cards = try buildTotpCards(allocator, entries);
    defer allocator.free(totp_cards);
    const readonly_cards = try buildReadonlyCards(allocator, entries);
    defer allocator.free(readonly_cards);

    var dash = dashboard.Dashboard.init(allocator, io, .{ .title = "ztotp" });
    defer dash.deinit();
    try dash.addSection("TOTP", totp_cards);
    try dash.addSection("Readonly", readonly_cards);
    try dash.run();
}

const EntryContext = struct {
    entry: model.Entry,
    timestamp: i64,
};

fn buildTotpCards(allocator: std.mem.Allocator, entries: []const model.Entry) ![]dashboard.Card {
    var list = std.ArrayList(dashboard.Card).empty;
    defer list.deinit(allocator);
    for (entries) |entry| {
        if (entry.kind != .totp or entry.isReadonly()) continue;
        try list.append(allocator, .{
            .width = card_width,
            .height = card_height_totp,
            .drawFn = drawTotpCard,
            .context = @ptrCast(@constCast(&entry)),
        });
    }
    return list.toOwnedSlice(allocator);
}

fn buildReadonlyCards(allocator: std.mem.Allocator, entries: []const model.Entry) ![]dashboard.Card {
    var list = std.ArrayList(dashboard.Card).empty;
    defer list.deinit(allocator);
    for (entries) |entry| {
        if (entry.kind == .totp and !entry.isReadonly()) continue;
        try list.append(allocator, .{
            .width = card_width,
            .height = card_height_readonly,
            .drawFn = drawReadonlyCard,
            .context = @ptrCast(@constCast(&entry)),
        });
    }
    return list.toOwnedSlice(allocator);
}

fn drawTotpCard(buf: *buffer.Buffer, rect: widgets.Rect, allocator: std.mem.Allocator, timestamp: i64, ctx: *anyopaque) !void {
    const entry: *const model.Entry = @ptrCast(@alignCast(ctx));
    const item = try view.entryView(allocator, entry.*, timestamp);
    widgets.boxSingle(buf, rect, .heading);
    widgets.label(buf, rect.x + 2, rect.y + 1, rect.width - 4, item.issuer, .accent);
    widgets.label(buf, rect.x + 2, rect.y + 2, rect.width - 4, item.account_name, .normal);
    widgets.label(buf, rect.x + 2, rect.y + 3, rect.width - 4, item.source_label, .source);
    widgets.label(buf, rect.x + 2, rect.y + 4, 5, "code", .muted);
    buf.putText(rect.x + 8, rect.y + 4, item.code.?[8 - item.code_len ..], .code);
    const filled = @min(16, (item.remaining_seconds * 16) / @max(1, item.period));
    widgets.progressBar(buf, rect.x + 2, rect.y + 6, 16, filled, .code, .muted);
    var countdown: [16]u8 = undefined;
    const text = try std.fmt.bufPrint(&countdown, "{d}s", .{item.remaining_seconds});
    widgets.label(buf, rect.x + 20, rect.y + 6, rect.width - 22, text, .muted);
}

fn drawReadonlyCard(buf: *buffer.Buffer, rect: widgets.Rect, allocator: std.mem.Allocator, timestamp: i64, ctx: *anyopaque) !void {
    _ = timestamp;
    const entry: *const model.Entry = @ptrCast(@alignCast(ctx));
    const item = try view.entryView(allocator, entry.*, 0);
    widgets.boxSingle(buf, rect, .muted);
    widgets.label(buf, rect.x + 2, rect.y + 1, rect.width - 4, item.issuer, .accent);
    widgets.label(buf, rect.x + 2, rect.y + 2, rect.width - 4, item.account_name, .normal);
    widgets.label(buf, rect.x + 2, rect.y + 3, rect.width - 4, item.source_label, .source);
    widgets.label(buf, rect.x + 2, rect.y + 4, rect.width - 4, item.kind_label, .badge);
    widgets.label(buf, rect.x + 2, rect.y + 5, rect.width - 4, item.readonly_reason orelse "imported", .readonly);
}
