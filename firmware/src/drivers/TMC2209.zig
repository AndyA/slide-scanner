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

pub const ReadDG = packed struct {
    comptime {
        assert(@sizeOf(ReadDG) == 4);
        assert(@offsetOf(ReadDG, "crc") == 3);
    }
    pub const Bytes = [@sizeOf(ReadDG)]u8;

    sync: u8 = 0b00000101,
    addr: u8,
    reg: Register,
    write: bool = false,
    crc: u8 = undefined,

    pub fn format(self: ReadDG, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("read {d}/{s} (crc {s})", .{
            self.addr,
            @tagName(self.reg),
            if (self.checkCrc()) "ok" else "bad",
        });
    }

    fn calcCrc(self: ReadDG) u8 {
        return calculateCrc(self.toSlice()[0..@offsetOf(ReadDG, "crc")]);
    }

    pub fn init(addr: u8, reg: Register) ReadDG {
        var self: ReadDG = .{ .addr = addr, .reg = reg };
        self.crc = self.calcCrc();
        return self;
    }

    pub fn checkCrc(self: ReadDG) bool {
        return self.calcCrc() == self.crc;
    }

    pub fn toSlice(self: *const ReadDG) []const u8 {
        return @ptrCast(self);
    }
};

test ReadDG {}

pub const DataDG = packed struct {
    comptime {
        assert(@sizeOf(DataDG) == 8);
        assert(@offsetOf(DataDG, "crc") == 7);
    }
    pub const Bytes = [@sizeOf(DataDG)]u8;

    sync: u8 = 0b00000101,
    addr: u8,
    reg: Register,
    write: bool,
    data: u32, // big endian
    crc: u8 = undefined,

    pub fn format(self: DataDG, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("data {s} {d}/{s} 0x{x:0>8} (crc {s})", .{
            if (self.write) "write" else "read",
            self.addr,
            @tagName(self.reg),
            self.value(),
            if (self.checkCrc()) "ok" else "bad",
        });
    }

    fn calcCrc(self: DataDG) u8 {
        return calculateCrc(self.toSlice()[0..@offsetOf(DataDG, "crc")]);
    }

    pub fn init(addr: u8, reg: Register, data: u32) DataDG {
        var self: DataDG = .{
            .addr = addr,
            .reg = reg,
            .write = true,
            .data = std.mem.nativeToBig(u32, data),
        };
        self.crc = self.calcCrc();
        return self;
    }

    pub fn value(self: DataDG) u32 {
        return std.mem.bigToNative(u32, self.data);
    }

    pub fn checkCrc(self: DataDG) bool {
        return self.calcCrc() == self.crc;
    }

    pub fn toSlice(self: *const DataDG) []const u8 {
        return @ptrCast(self);
    }

    pub fn toMutableSlice(self: *DataDG) []u8 {
        return @ptrCast(self);
    }
};

test DataDG {
    const dg: DataDG = .init(1, .FACTORY_CONF, 0x12345678);
    try std.testing.expect(dg.checkCrc());
    try std.testing.expectEqual(0x12345678, dg.value());
}

pub const Datagram = union(enum) {
    read: ReadDG,
    data: DataDG,

    pub fn initRead(addr: u8, reg: Register) Datagram {
        return .{ .read = .init(addr, reg) };
    }

    pub fn initWrite(addr: u8, reg: Register, data: u32) Datagram {
        return .{ .data = .init(addr, reg, data) };
    }

    pub fn checkCrc(self: Datagram) bool {
        return switch (self) {
            inline else => |x| x.checkCrc(),
        };
    }

    pub fn toSlice(self: *const Datagram) []const u8 {
        return switch (self.*) {
            inline else => |*x| x.toSlice(),
        };
    }

    pub fn format(self: Datagram, w: *std.Io.Writer) std.Io.Writer.Error!void {
        return switch (self) {
            inline else => |x| x.format(w),
        };
    }
};

test Datagram {
    const rdg: Datagram = .initRead(0, .PWMCONF);
    try std.testing.expect(rdg.checkCrc());
    try std.testing.expectEqual(4, rdg.toSlice().len);
    if (false) {
        const foo: []const u8 = @ptrCast(&rdg.read);
        std.debug.print(
            "rdg.toSlice={any} rdg.read.toSlice={any} foo={any}\n",
            .{ rdg.toSlice(), rdg.read.toSlice(), foo },
        );
    }
    const ddg: Datagram = .initWrite(0, .PWMCONF, 0xaa);
    try std.testing.expect(ddg.checkCrc());
    try std.testing.expectEqual(8, ddg.toSlice().len);
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
        data: DataDG,
        ready: void,
        err: void,
        timeout: void,
    };

    const Emitter = events.Emitter(Event, 5);

    const RETRY_DELAY = time.Duration.from_ms(1);
    const TIMEOUT = time.Duration.from_ms(1000);

    u: hal.uart.UART,
    rx_pin: hal.gpio.Pin,
    tx_pin: hal.gpio.Pin,
    state: State = .IDLE,
    ee: Emitter = .empty,

    tx_dg: Datagram = undefined,
    rx_dg: DataDG = undefined,

    pos: u8 = undefined,
    tries: u8 = undefined,
    delay: time.Absolute = undefined,
    timeout: time.Absolute = undefined,

    pub fn init(u: hal.uart.UART, rx_pin: hal.gpio.Pin, tx_pin: hal.gpio.Pin) Self {
        const self: Self = .{
            .u = u,
            .rx_pin = rx_pin,
            .tx_pin = tx_pin,
        };
        self.setWriting(true);
        return self;
    }

    fn setWriting(self: Self, enable: bool) void {
        const regs = self.u.get_regs();
        regs.UARTCR.modify(.{ .TXE = @as(u1, if (enable) 1 else 0) });
    }

    fn writeNonBlocking(self: *Self) void {
        const regs = self.u.get_regs();
        const dg = self.tx_dg.toSlice();
        assert(self.pos < dg.len);
        while (self.pos < dg.len and self.u.is_writeable()) {
            regs.UARTDR.write_raw(dg[self.pos]);
            self.pos += 1;
        }
    }

    fn emitAndIdle(self: *Self, event: Event) void {
        self.goState(.IDLE);
        self.ee.emit(event) catch {};
    }

    fn readByte(self: *Self) !?u8 {
        return self.u.read_word() catch |e| {
            self.u.clear_errors();
            if (self.tries == 0) {
                self.emitAndIdle(.{ .err = {} });
            } else {
                self.tries -= 1;
                const now = hal.time.get_time_since_boot();
                self.delay = now.add_duration(RETRY_DELAY);
                self.goState(.RETRY_WAIT);
            }
            return e;
        };
    }

    fn discardNonBlocking(self: *Self) !void {
        const dg_len = self.tx_dg.toSlice().len;
        assert(self.pos < dg_len);
        while (self.pos < dg_len) : (self.pos += 1) {
            if (try self.readByte() == null) break;
        }
    }

    fn readNonBlocking(self: *Self) !void {
        var dg = self.rx_dg.toMutableSlice();
        assert(self.pos < dg.len);
        while (self.pos < dg.len) : (self.pos += 1) {
            if (try self.readByte()) |b|
                dg[self.pos] = b
            else
                break;
        }
    }

    pub fn send(self: *Self, dg: Datagram) void {
        assert(self.state == .IDLE);
        assert(dg.checkCrc());
        self.tx_dg = dg;
        self.tries = 5;
        self.timeout = hal.time.get_time_since_boot().add_duration(TIMEOUT);
        self.goState(.WRITING);
    }

    fn goState(self: *Self, state: State) void {
        self.state = state;
        self.pos = 0;
    }

    pub fn poll(self: *Self) void {
        const now = hal.time.get_time_since_boot();

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
                if (self.pos == self.tx_dg.toSlice().len) {
                    self.goState(.DISCARDING);
                }
            },
            .DISCARDING => {
                self.discardNonBlocking() catch return;
                if (self.pos == self.tx_dg.toSlice().len) {
                    if (self.tx_dg == .data) {
                        self.emitAndIdle(.{ .ready = {} });
                    } else {
                        self.goState(.READING);
                    }
                }
            },
            .READING => {
                self.readNonBlocking() catch return;
                if (self.pos == self.rx_dg.toSlice().len) {
                    self.emitAndIdle(.{ .data = self.rx_dg });
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
