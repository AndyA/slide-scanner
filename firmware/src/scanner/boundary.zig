const std = @import("std");

pub fn Boundaries(comptime I: type, comptime size: u8) type {
    return struct {
        boundaries: [size]I,
        current_boundary: u8,
        current_pos: I,
    };
}
