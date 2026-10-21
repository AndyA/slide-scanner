//! Generate CRCs for the TMC2209 stepper controller.
//! Ref: https://www.analog.com/media/en/technical-documentation/data-sheets/TMC2209_datasheet_rev1.09.pdf
const std = @import("std");

fn nextCrc(old_crc: u8, byte: u8) u8 {
    var work = byte;
    var crc = old_crc;
    for (0..8) |_| {
        if ((crc >> 7) ^ (work & 0x01) != 0)
            crc = (crc << 1) ^ 0x07
        else
            crc = crc << 1;
        work = work >> 1;
    }
    return crc;
}

fn calcCrcRef(data: []const u8) u8 {
    var crc: u8 = 0;
    for (data) |byte| {
        crc = nextCrc(crc, byte);
    }
    return crc;
}

const lookup = blk: {
    @setEvalBranchQuota(25000);
    var table: [256]u8 = undefined;
    for (&table, 0..) |*e, i| {
        e.* = @bitReverse(nextCrc(0, @intCast(i)));
    }
    break :blk table;
};

pub fn calcCrc(data: []const u8) u8 {
    var crc: u8 = 0;
    for (data) |byte| {
        crc = lookup[crc ^ byte];
    }
    return @bitReverse(crc);
}

test calcCrc {
    const test_data = "Hello, World etc";
    for (0..test_data.len) |limit| {
        const slice = test_data[0 .. limit + 1];
        const ref_crc = calcCrcRef(slice);
        const fast_crc = calcCrc(slice);
        try std.testing.expectEqual(ref_crc, fast_crc);
    }
}
