const std = @import("std");
const assert = std.debug.assert;

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
    @setEvalBranchQuota(3000);
    var table: [256]u8 = undefined;
    for (&table, 0..) |*e, i| {
        e.* = @bitReverse(nextCrc(0, @intCast(i)));
    }
    break :blk table;
};

pub fn calculateCrc(data: []const u8) u8 {
    var crc: u8 = 0;
    for (data) |byte| {
        crc = lookup[crc ^ byte];
    }
    return @bitReverse(crc);
}

test calculateCrc {
    var prng: std.Random.DefaultPrng = .init(123);
    var test_data: [256]u8 = undefined;
    prng.random().bytes(&test_data);
    for (0..test_data.len) |limit| {
        const slice = test_data[0 .. limit + 1];
        const ref_crc = calcCrcRef(slice);
        const fast_crc = calculateCrc(slice);
        try std.testing.expectEqual(ref_crc, fast_crc);
    }
}

pub const Register = enum(u7) {
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
    TCOOLTHRS = 0x14, // W
    VACTUAL = 0x22, // W
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

const Datagram = packed struct {
    const Bytes = [@sizeOf(Datagram)]u8;

    sync: u8 = 0b00000101,
    addr: u8,
    reg: Register,
    write: bool,
    data: u32, // big endian
    crc: u8 = undefined,

    comptime {
        assert(@sizeOf(Datagram) == 8);
        assert(@offsetOf(Datagram, "crc") == 7);
    }

    pub fn initRead(addr: u8, reg: Register) Datagram {
        var self: Datagram = .{
            .addr = addr,
            .reg = reg,
            .write = false,
            .data = 0,
        };
        self.crc = self.calcCrc();
        return self;
    }

    pub fn initWrite(addr: u8, reg: Register, data: u32) Datagram {
        var self: Datagram = .{
            .addr = addr,
            .reg = reg,
            .write = true,
            .data = std.mem.nativeToBig(u32, data),
        };
        self.crc = self.calcCrc();
        return self;
    }

    pub fn initBytes(bytes: Bytes) Datagram {
        return @bitCast(bytes);
    }

    pub fn value(self: Datagram) u32 {
        return std.mem.bigToNative(u32, self.data);
    }

    pub fn checkCrc(self: Datagram) bool {
        return self.calcCrc() == self.crc;
    }

    fn calcCrc(self: Datagram) u8 {
        return calculateCrc(self.toBytes()[0..@offsetOf(Datagram, "crc")]);
    }

    fn toBytes(self: Datagram) Bytes {
        return @bitCast(self);
    }
};

test Datagram {
    const dg: Datagram = .initWrite(1, .FACTORY_CONF, 0x12345678);
    try std.testing.expect(dg.checkCrc());
    try std.testing.expectEqual(0x12345678, dg.value());

    const dg2: Datagram = .initBytes(dg.toBytes());
    try std.testing.expectEqual(0x12345678, dg2.value());
    try std.testing.expectEqual(.FACTORY_CONF, dg2.reg);
    try std.testing.expect(dg2.checkCrc());
}
