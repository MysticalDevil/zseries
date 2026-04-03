const std = @import("std");
const buffer = @import("../buffer.zig");
const widgets = @import("core.zig");
const style = @import("../style.zig");
const input_mod = @import("../input.zig");
const terminal = @import("../terminal.zig");

pub const Card = struct {
    width: usize,
    height: usize,
    drawFn: *const fn (buf: *buffer.Buffer, rect: widgets.Rect, allocator: std.mem.Allocator, timestamp: i64, context: *anyopaque) anyerror!void,
    context: *anyopaque,
};

pub const Section = struct {
    title: []const u8,
    cards: []const Card,
};

pub const DashboardConfig = struct {
    title: []const u8 = "dashboard",
    card_gap: usize = 2,
    refresh_ms: u32 = 250,
};

pub const Dashboard = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    config: DashboardConfig,
    sections: std.ArrayList(Section),
    query: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, io: std.Io, config: DashboardConfig) Dashboard {
        return .{
            .allocator = allocator,
            .io = io,
            .config = config,
            .sections = .empty,
            .query = .empty,
        };
    }

    pub fn deinit(self: *Dashboard) void {
        self.query.deinit(self.allocator);
        self.sections.deinit(self.allocator);
    }

    pub fn addSection(self: *Dashboard, title: []const u8, cards: []const Card) !void {
        try self.sections.append(self.allocator, .{ .title = title, .cards = cards });
    }

    pub fn run(self: *Dashboard) !void {
        const raw = try input_mod.RawMode.enter();
        defer raw.leave();
        try terminal.enterScreen();
        defer terminal.restoreScreen() catch {};

        var last_hash: ?u64 = null;
        var last_size: ?u64 = null;

        while (true) {
            const frame = try self.renderFrame();
            defer self.allocator.free(frame.text);

            const changed = last_hash == null or last_hash.? != frame.hash;
            const current_size = (@as(u64, frame.width) << 32) | @as(u64, frame.height);
            const size_changed = last_size == null or last_size.? != current_size;

            if (changed) {
                if (size_changed) {
                    try terminal.clearScreen();
                } else {
                    try terminal.homeCursor();
                }
                try terminal.writeStdout(frame.text);
                last_hash = frame.hash;
                last_size = current_size;
            }

            switch (try input_mod.readEvent(@intCast(self.config.refresh_ms))) {
                .none => continue,
                .quit => break,
                .clear_search => self.query.clearRetainingCapacity(),
                .backspace => if (self.query.items.len > 0) self.query.shrinkRetainingCapacity(self.query.items.len - 1),
                .character => |ch| try self.query.append(self.allocator, ch),
            }
        }
    }

    const Frame = struct {
        text: []u8,
        width: usize,
        height: usize,
        hash: u64,
    };

    fn renderFrame(self: *Dashboard) !Frame {
        const width = terminalWidth();
        var total_height: usize = 2;
        for (self.sections.items) |section| {
            const per_row = cardsPerRow(width, self.config.card_gap);
            const card_height = maxCardHeight(section.cards);
            total_height += sectionHeight(section.cards.len, per_row, card_height);
        }

        var buf = try buffer.Buffer.init(self.allocator, width, total_height);
        defer buf.deinit();
        buf.clear(.normal);

        buf.putText(0, 0, self.config.title, .title);
        const search_label = "search:";
        buf.putText(self.config.title.len + 2, 0, search_label, .muted);
        buf.putText(self.config.title.len + 2 + search_label.len, 0, self.query.items, .normal);
        buf.putText(width - 8, 0, "q quit", .muted);

        var y: usize = 2;
        for (self.sections.items) |section| {
            y = try self.drawSection(&buf, section, y, width);
        }

        const text = try buf.renderAlloc();
        return .{
            .text = text,
            .width = width,
            .height = total_height,
            .hash = std.hash.Wyhash.hash(0, text),
        };
    }

    fn drawSection(self: *Dashboard, buf: *buffer.Buffer, section: Section, start_y: usize, width: usize) !usize {
        var heading: [64]u8 = undefined;
        const heading_text = try std.fmt.bufPrint(&heading, "{s} ({d})", .{ section.title, section.cards.len });
        buf.putText(0, start_y, heading_text, .heading);

        if (section.cards.len == 0) {
            buf.putText(2, start_y + 2, "no entries", .muted);
            return start_y + 3;
        }

        const per_row = cardsPerRow(width, self.config.card_gap);
        const card_height = maxCardHeight(section.cards);
        const timestamp = std.Io.Clock.real.now(self.io).toSeconds();

        for (section.cards, 0..) |card, i| {
            const row = i / per_row;
            const col = i % per_row;
            const x = col * (card.width + self.config.card_gap);
            const y = start_y + 2 + row * (card.height + 1);
            const rect = widgets.Rect{ .x = x, .y = y, .width = card.width, .height = card.height };
            try card.drawFn(buf, rect, self.allocator, timestamp, card.context);
        }

        return start_y + 2 + @divFloor(section.cards.len + per_row - 1, per_row) * (card_height + 1);
    }
};

fn terminalWidth() usize {
    if (@import("builtin").os.tag == .linux) {
        const linux = std.os.linux;
        var wsz: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        const rc = linux.syscall3(.ioctl, @bitCast(@as(isize, std.posix.STDOUT_FILENO)), linux.T.IOCGWINSZ, @intFromPtr(&wsz));
        if (linux.errno(rc) == .SUCCESS and wsz.col > 0) return wsz.col;
    }
    return 120;
}

fn cardsPerRow(width: usize, gap: usize) usize {
    return @max(1, width / (36 + gap));
}

fn maxCardHeight(cards: []const Card) usize {
    var max_h: usize = 0;
    for (cards) |card| {
        if (card.height > max_h) max_h = card.height;
    }
    return max_h;
}

fn sectionHeight(count: usize, per_row: usize, card_height: usize) usize {
    if (count == 0) return 3;
    const rows = @divFloor(count + per_row - 1, per_row);
    return 2 + rows * (card_height + 1);
}
