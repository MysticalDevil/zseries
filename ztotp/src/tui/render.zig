const std = @import("std");
const model = @import("../model.zig");
const style = @import("ztui").style;
const view = @import("view.zig");
const buffer = @import("ztui").buffer;
const widgets = @import("ztui").widgets;

const card_width = 36;
const card_height_totp = 8;
const card_height_readonly = 7;
const card_gap = 2;

pub const Partition = struct {
    totp: []usize,
    readonly: []usize,

    pub fn deinit(self: Partition, allocator: std.mem.Allocator) void {
        allocator.free(self.totp);
        allocator.free(self.readonly);
    }
};

pub const RenderedDashboard = struct {
    frame: []u8,
    width: usize,
    height: usize,
    totp_count: usize,
    readonly_count: usize,
    frame_hash: u64,

    pub fn deinit(self: RenderedDashboard, allocator: std.mem.Allocator) void {
        allocator.free(self.frame);
    }
};

pub fn partitionAlloc(allocator: std.mem.Allocator, entries: []const model.Entry, query: []const u8) !Partition {
    var totp_indexes = std.ArrayList(usize).empty;
    defer totp_indexes.deinit(allocator);
    var readonly_indexes = std.ArrayList(usize).empty;
    defer readonly_indexes.deinit(allocator);

    for (entries, 0..) |entry, index| {
        if (!view.matchesSearch(entry, query)) continue;
        if (entry.kind == .totp and !entry.isReadonly()) {
            try totp_indexes.append(allocator, index);
        } else {
            try readonly_indexes.append(allocator, index);
        }
    }

    return .{
        .totp = try totp_indexes.toOwnedSlice(allocator),
        .readonly = try readonly_indexes.toOwnedSlice(allocator),
    };
}

fn terminalWidth() usize {
    if (@import("builtin").os.tag == .linux) {
        const linux = std.os.linux;
        var wsz: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        const rc = linux.syscall3(.ioctl, @bitCast(@as(isize, std.posix.STDOUT_FILENO)), linux.T.IOCGWINSZ, @intFromPtr(&wsz));
        if (linux.errno(rc) == .SUCCESS and wsz.col > 0) return wsz.col;
    }
    return 120;
}

fn cardsPerRow(width: usize) usize {
    return @max(1, width / (card_width + card_gap));
}

fn drawTotpCard(buf: *buffer.Buffer, rect: widgets.Rect, entry: model.Entry, timestamp: i64, allocator: std.mem.Allocator) !void {
    const item = try view.entryView(allocator, entry, timestamp);
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

fn drawReadonlyCard(buf: *buffer.Buffer, rect: widgets.Rect, entry: model.Entry, timestamp: i64, allocator: std.mem.Allocator) !void {
    const item = try view.entryView(allocator, entry, timestamp);
    widgets.boxSingle(buf, rect, .muted);
    widgets.label(buf, rect.x + 2, rect.y + 1, rect.width - 4, item.issuer, .accent);
    widgets.label(buf, rect.x + 2, rect.y + 2, rect.width - 4, item.account_name, .normal);
    widgets.label(buf, rect.x + 2, rect.y + 3, rect.width - 4, item.source_label, .source);
    widgets.label(buf, rect.x + 2, rect.y + 4, rect.width - 4, item.kind_label, .badge);
    widgets.label(buf, rect.x + 2, rect.y + 5, rect.width - 4, item.readonly_reason orelse "imported", .readonly);
}

fn sectionHeight(count: usize, per_row: usize, card_height: usize) usize {
    if (count == 0) return 3;
    const rows = @divFloor(count + per_row - 1, per_row);
    return 1 + rows * (card_height + 1);
}

fn drawSection(buf: *buffer.Buffer, allocator: std.mem.Allocator, entries: []const model.Entry, indexes: []const usize, title: []const u8, start_y: usize, timestamp: i64, width: usize, readonly_section: bool) !usize {
    const per_row = cardsPerRow(width);
    const card_height: usize = if (readonly_section) card_height_readonly else card_height_totp;
    var heading: [64]u8 = undefined;
    const heading_text = try std.fmt.bufPrint(&heading, "{s} ({d})", .{ title, indexes.len });
    buf.putText(0, start_y, heading_text, .heading);
    if (indexes.len == 0) {
        buf.putText(2, start_y + 2, "no entries", .muted);
        return start_y + 3;
    }

    for (indexes, 0..) |entry_index, i| {
        const row = i / per_row;
        const col = i % per_row;
        const x = col * (card_width + card_gap);
        const y = start_y + 2 + row * (card_height + 1);
        const rect = widgets.Rect{ .x = x, .y = y, .width = card_width, .height = card_height };
        if (readonly_section) {
            try drawReadonlyCard(buf, rect, entries[entry_index], timestamp, allocator);
        } else {
            try drawTotpCard(buf, rect, entries[entry_index], timestamp, allocator);
        }
    }
    return start_y + sectionHeight(indexes.len, per_row, card_height);
}

pub fn renderDashboardAlloc(allocator: std.mem.Allocator, entries: []const model.Entry, query: []const u8, timestamp: i64) !RenderedDashboard {
    const partition = try partitionAlloc(allocator, entries, query);
    defer partition.deinit(allocator);
    const width = terminalWidth();
    const per_row = cardsPerRow(width);
    const height = 4 + sectionHeight(partition.totp.len, per_row, card_height_totp) + sectionHeight(partition.readonly.len, per_row, card_height_readonly) + 2;
    var buf = try buffer.Buffer.init(allocator, width, height);
    defer buf.deinit();
    buf.clear(.normal);
    buf.putText(0, 0, "ztotp", .title);
    buf.putText(8, 0, "search:", .muted);
    buf.putText(16, 0, query, .normal);
    buf.putText(width - 18, 0, "q quit", .muted);
    buf.putText(width - 10, 0, "esc clear", .muted);
    const next_y = try drawSection(&buf, allocator, entries, partition.totp, "TOTP", 2, timestamp, width, false);
    _ = try drawSection(&buf, allocator, entries, partition.readonly, "Readonly", next_y + 1, timestamp, width, true);
    const frame = try buf.renderAlloc();
    return .{
        .frame = frame,
        .width = width,
        .height = height,
        .totp_count = partition.totp.len,
        .readonly_count = partition.readonly.len,
        .frame_hash = std.hash.Wyhash.hash(0, frame),
    };
}

test "partition separates totp and readonly" {
    const testing = std.testing;
    const entries = [_]model.Entry{
        .{ .id = "1", .issuer = "GitHub", .account_name = "alice", .secret = "AAA", .created_at = 0, .updated_at = 0 },
        .{ .id = "2", .issuer = "Steam", .account_name = "bob", .secret = "BBB", .kind = .steam, .readonly_reason = "imported_non_totp", .created_at = 0, .updated_at = 0 },
    };
    const partition = try partitionAlloc(testing.allocator, &entries, "");
    defer partition.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), partition.totp.len);
    try testing.expectEqual(@as(usize, 1), partition.readonly.len);
}
