const std = @import("std");
const buffer = @import("../buffer.zig");
const style = @import("../style.zig");

pub const SpinnerConfig = struct {
    x: usize = 0,
    y: usize = 0,
    style_id: style.StyleId = .accent,
};

pub const Spinner = struct {
    config: SpinnerConfig,
    frame: usize = 0,
    const frames = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };

    pub fn draw(self: Spinner, buf: *buffer.Buffer) void {
        buf.putText(self.config.x, self.config.y, frames[self.frame % frames.len], self.config.style_id);
    }

    pub fn advance(self: *Spinner) void {
        self.frame = (self.frame + 1) % frames.len;
    }

    pub fn reset(self: *Spinner) void {
        self.frame = 0;
    }
};

test "Spinner cycles through frames" {
    const testing = std.testing;
    var buf = try buffer.Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();

    var spinner = Spinner{ .config = .{} };
    spinner.draw(&buf);
    try testing.expect(spinner.frame < Spinner.frames.len);
    spinner.advance();
    try testing.expect(spinner.frame == 1);
}
