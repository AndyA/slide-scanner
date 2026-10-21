const std = @import("std");

fn calcCrc(data: []const u8) u8 {
    var crc: u8 = 0;
    for (data) |byte| {
        var work = byte;
        for (0..8) |_| {
            if ((crc >> 7) ^ (work & 0x01) != 0)
                crc = (crc << 1) ^ 0x07
            else
                crc = crc << 1;
            work = work >> 1;
        }
    }
    return crc;
}

pub fn main() void {
    const test_data = "Hello, World etc";
    const ref_crc = calcCrc(test_data);
    std.debug.print("ref_crc: {x}\n", .{ref_crc});
}

test {
    _ = @import("runtime/events.zig");
    _ = @import("runtime/tools.zig");
}
