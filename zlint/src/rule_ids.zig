const std = @import("std");

pub const discarded_result = "discarded_result";
pub const max_anytype_params = "max_anytype_params";
pub const no_silent_error_handling = "no_silent_error_handling";
pub const catch_unreachable = "catch_unreachable";
pub const defer_return_invalid = "defer_return_invalid";
pub const unused_allocator = "unused_allocator";
pub const global_allocator_in_lib = "global_allocator_in_lib";
pub const no_do_not_optimize_away = "no_do_not_optimize_away";
pub const duplicated_code = "duplicated_code";
pub const discard_assignment = "discard_assignment";
pub const no_anytype_io_params = "no_anytype_io_params";

pub const all: []const []const u8 = &.{
    discarded_result,
    max_anytype_params,
    no_silent_error_handling,
    catch_unreachable,
    defer_return_invalid,
    unused_allocator,
    global_allocator_in_lib,
    no_do_not_optimize_away,
    duplicated_code,
    discard_assignment,
    no_anytype_io_params,
};

pub fn isKnown(rule_id: []const u8) bool {
    for (all) |candidate| {
        if (std.mem.eql(u8, candidate, rule_id)) return true;
    }
    return false;
}
