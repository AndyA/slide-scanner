const std = @import("std");
const assert = std.debug.assert;

const calculateCrc = @import("runtime/crc.zig").calculateCrc;

pub const TMC2209Register = enum(u7) {
    GCONF = 0x00, // RW
    GSTAT = 0x01, // R+WC
    IFCNT = 0x02, // R
    NODECONF = 0x03, // W
    OTP_PROG = 0x04, // W
    OTP_READ = 0x05, // R
    IOIN = 0x06, // R
    FACTORY_CONF = 0x07, // RW
    IHOLD_IRUN = 0x10, // W
    TPOWERDOWN = 0x11, // W
    TSTEP = 0x12, // R
    TPWMTHRS = 0x13, // W
    VACTUAL = 0x22, // W
    TCOOLTHRS = 0x14, // W
    SGTHRS = 0x40, // W
    SG_RESULT = 0x41, // R
    COOLCONF = 0x42, // W
    MSCNT = 0x6A, // R
    MSCURACT = 0x6B, // R
    CHOPCONF = 0x6C, // RW
    DRV_STATUS = 0x6F, // R
    PWMCONF = 0x70, // RW
    PWM_SCALE = 0x71, // R
    PWM_AUTO = 0x72, // R
};

const TMC2209Datagram = packed struct {
    const Self = @This();
    const Bytes = [@sizeOf(Self)]u8;

    sync: u8 = 0b00000101,
    addr: u8,
    reg: TMC2209Register,
    write: bool,
    data: u32, // big endian
    crc: u8 = undefined,

    comptime {
        assert(@sizeOf(Self) == 8);
        assert(@offsetOf(Self, "crc") == 7);
    }

    pub fn initRead(addr: u8, reg: TMC2209Register) Self {
        var self: Self = .{
            .addr = addr,
            .reg = reg,
            .write = false,
            .data = 0,
        };
        self.generateCrc();
        return self;
    }

    pub fn initWrite(addr: u8, reg: TMC2209Register, data: u32) Self {
        var self: Self = .{
            .addr = addr,
            .reg = reg,
            .write = true,
            .data = std.mem.nativeToBig(u32, data),
        };
        self.generateCrc();
        return self;
    }

    pub fn initBytes(bytes: Bytes) Self {
        return @bitCast(bytes);
    }

    pub fn value(self: Self) u32 {
        return std.mem.bigToNative(u32, self.data);
    }

    pub fn checkCrc(self: Self) bool {
        return generateCrc(self) == self.crc;
    }

    fn generateCrc(self: *Self) void {
        self.crc = self.calcCrc();
    }

    fn asBytes(self: Self) Bytes {
        return @bitCast(self);
    }

    fn calcCrc(self: Self) u8 {
        return calculateCrc(self.asBytes()[0..@offsetOf(Self, "crc")]);
    }
};

test TMC2209Datagram {
    const dg: TMC2209Datagram = .initWrite(1, .FACTORY_CONF, 0x12345678);
    try std.testing.expectEqual(0x12345678, dg.value());
    const dg2: TMC2209Datagram = .initBytes(dg.asBytes());
    try std.testing.expectEqual(0x12345678, dg2.value());
    try std.testing.expectEqual(.FACTORY_CONF, dg2.reg);
}

pub fn main() void {
    std.debug.print("Hello!\n", .{});
}

test {
    _ = @import("runtime/crc.zig");
    _ = @import("runtime/events.zig");
    _ = @import("runtime/tools.zig");
}
