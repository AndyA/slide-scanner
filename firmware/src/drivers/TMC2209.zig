const std = @import("std");
const assert = std.debug.assert;
const microzig = @import("microzig");
const hal = microzig.hal;
const time = microzig.drivers.time;
const events = @import("../runtime/events.zig");

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

pub const Datagram = packed struct {
    comptime {
        assert(@sizeOf(Datagram) == 8);
        assert(@offsetOf(Datagram, "crc") == 7);
    }
    pub const Bytes = [@sizeOf(Datagram)]u8;

    sync: u8 = 0b00000101,
    addr: u8,
    reg: Register,
    write: bool,
    data: u32, // big endian
    crc: u8 = undefined,

    fn calcCrc(self: Datagram) u8 {
        return calculateCrc(self.toBytes()[0..@offsetOf(Datagram, "crc")]);
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

    pub fn toBytes(self: Datagram) Bytes {
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

pub const SerialIO = struct {
    const Self = @This();

    pub const State = enum(u8) {
        IDLE,
        WRITING,
        DISCARDING,
        READING,
        RETRY_WAIT,
    };

    pub const Event = union(enum) {
        err: void,
        timeout: void,
        received: Datagram,
    };

    const Emitter = events.Emitter(Event, 5);

    const RETRY_DELAY = time.Duration.from_ms(1);
    const TIMEOUT = time.Duration.from_ms(100);

    u: hal.uart.UART,
    state: State = .IDLE,
    ee: Emitter = .empty,
    tx_buf: Datagram.Bytes = undefined,
    rx_buf: Datagram.Bytes = undefined,
    pos: u8 = undefined,
    tries: u8 = undefined,
    delay: time.Absolute = undefined,
    timeout: time.Absolute = undefined,

    pub fn init(u: hal.uart.UART) Self {
        const self = .{ .u = u };
        self.setWriting(1);
        return self;
    }

    fn setWriting(self: Self, enable: bool) void {
        const regs = self.u.get_regs();
        regs.UARTCR.modify(.{ .TXE = @intCast(enable) });
    }

    fn writeNonBlocking(self: *Self) void {
        const regs = self.u.get_regs();
        assert(self.pos < self.tx_buf.len);
        while (self.pos < self.tx_buf.len and self.u.is_writeable()) {
            regs.UARTDR.write_raw(self.tx_buf[self.pos]);
            self.pos += 1;
        }
    }

    fn emitAndIdle(self: *Self, event: Event) void {
        self.ee.emit(event) catch {};
        self.goState(.IDLE);
    }

    fn readByte(self: *Self) !?u8 {
        return self.u.read_word() catch |e| {
            self.u.clear_errors();
            if (self.tries == 0) {
                self.emitAndIdle(.{ .err = {} });
            } else {
                self.tries -= 1;
                const now = time.get_time_since_boot();
                self.delay = now.add_duration(RETRY_DELAY);
                self.goState(.RETRY_WAIT);
            }
            return e;
        };
    }

    fn discardNonBlocking(self: *Self) !void {
        assert(self.pos < self.tx_buf.len);
        while (self.pos < self.tx_buf.len) : (self.pos += 1) {
            if (try self.readByte() == null) break;
        }
    }

    fn readNonBlocking(self: *Self) !void {
        assert(self.pos < self.rx_buf.len);
        while (self.pos < self.rx_buf.len) : (self.pos += 1) {
            if (try self.readByte()) |b|
                self.rx_buf[self.pos] = b
            else
                break;
        }
    }

    pub fn send(self: *Self, dg: Datagram) void {
        assert(self.state == .IDLE);
        self.tx_buf = dg.toBytes();
        self.tries = 5;
        self.timeout = time.get_time_since_boot.add_duration(TIMEOUT);
        self.goState(.WRITING);
    }

    fn goState(self: *Self, state: State) void {
        self.state = state;
        self.pos = 0;
        // self.setWriting(state == .WRITING);
    }

    pub fn poll(self: *Self) void {
        const now = time.get_time_since_boot();

        if (self.state != .IDLE) {
            if (self.timeout.is_reached_by(now)) {
                self.emitAndIdle(.{ .timeout = {} });
                return;
            }
        }

        switch (self.state) {
            .IDLE => {},
            .WRITING => {
                self.writeNonBlocking();
                if (self.pos == self.tx_buf.len) {
                    self.goState(.DISCARDING);
                }
            },
            .DISCARDING => {
                self.discardNonBlocking() catch return;
                if (self.pos == self.tx_buf.len) {
                    self.goState(.READING);
                }
            },
            .READING => {
                self.readNonBlocking() catch return;
                if (self.pos == self.rx_buf.len) {
                    self.emitAndIdle(.{ .received = Datagram.initBytes(&self.rx_buf) });
                }
            },
            .RETRY_WAIT => {
                if (self.delay.is_reached_by(now)) {
                    self.goState(.WRITING);
                }
            },
        }
    }
};
