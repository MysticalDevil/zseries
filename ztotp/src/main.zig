const std = @import("std");
const cli = @import("cli.zig");

fn printUserError(err: anyerror) void {
    switch (err) {
        error.InvalidArgs => std.debug.print("Invalid arguments. Run 'ztotp help' for usage.\n", .{}),
        error.EntryNotFound => std.debug.print("No matching entry found.\n", .{}),
        error.VaultMissing => std.debug.print("No vault found. Run 'ztotp init' first.\n", .{}),
        error.VaultAlreadyExists => std.debug.print("Vault already exists.\n", .{}),
        error.NotATerminal => std.debug.print("This command requires an interactive terminal.\n", .{}),
        else => std.debug.print("Error: {s}\n", .{@errorName(err)}),
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = init.minimal.args.toSlice(allocator) catch |err| {
        printUserError(err);
        std.process.exit(1);
    };
    cli.run(allocator, init.io, init.environ_map, args) catch |err| {
        printUserError(err);
        std.process.exit(1);
    };
}
