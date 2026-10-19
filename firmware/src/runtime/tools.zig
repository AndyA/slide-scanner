const std = @import("std");
const assert = std.debug.assert;

pub fn enumSize(comptime Enum: type) u8 {
    const info = @typeInfo(Enum).@"enum";
    var seen: u256 = 0;
    for (info.field_values) |value| {
        assert(value < 256);
        const mask: u256 = 1 << @intCast(value);
        assert((seen & mask) == 0);
        seen |= mask;
    }
    const unused = @clz(seen);
    assert(seen == (std.math.maxInt(u256) - 1) >> unused);
    return 256 - unused;
}

test enumSize {
    comptime {
        const en = enum(u8) { a, b, c };
        try std.testing.expectEqual(3, enumSize(en));
    }
}
