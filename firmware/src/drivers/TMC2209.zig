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

pub const RegValue = union(Register) {
    const Self = @This();

    GCONF: packed struct(u32) {
        i_scale_analog: bool = true,
        internal_rsense: bool = false, // OTP default
        en_spreadcycle: bool = false, // OTP default
        shaft: bool = false,
        index_otpw: bool = false,
        index_step: bool = false,
        pdn_disable: bool = true, // Desired for UART use
        mstep_reg_select: bool = true, // Desired for UART use
        multistep_filt: bool = false,
        test_mode: bool = false,
        _0: u22 = 0,
    },
    GSTAT: packed struct(u32) {
        reset: bool,
        drv_err: bool,
        uv_cp: bool,
        _0: u29 = 0,
    },
    IFCNT: packed struct(u32) {
        count: u8,
        _0: u24,
    },
    NODECONF: packed struct(u32) {
        _0: u8 = 0,
        send_delay: u4,
        _1: u20 = 0,
    },
    OTP_PROG: packed struct(u32) {
        bit: u3,
        byte: u2,
        _0: u3 = 0,
        magic: u8 = 0xbd,
        _1: u16 = 0,
    },
    OTP_READ: packed struct(u32) {
        otp0: u8,
        otp1: u8,
        otp2: u8,
        _0: u8,
    },
    IOIN: packed struct(u32) {
        en: bool,
        _0: u1,
        ms1: bool,
        ms2: bool,
        diag: bool,
        _1: u1,
        pdn_uart: bool,
        step: bool,
        spread_en: bool,
        dir: bool,
        _2: u14,
        version: u8,
    },
    FACTORY_CONF: packed struct(u32) {
        fclk_trim: u5,
        _0: u3,
        ot_trim: u2,
        _1: u22,
    },
    IHOLD_IRUN: packed struct(u32) {
        hold: u5,
        _0: u3,
        run: u5,
        _1: u3,
        hold_delay: u4,
        _2: u12,
    },
    TPOWERDOWN: u32,
    TSTEP: packed struct(u32) {
        step: u20,
        _0: u12,
    },
    TPWMTHRS: u32,
    TCOOLTHRS: u32,
    VACTUAL: i32,
    SGTHRS: u32,
    SG_RESULT: u32,
    COOLCONF: u32,
    MSCNT: u32,
    MSCURACT: u32,
    CHOPCONF: u32,
    DRV_STATUS: packed struct(u32) {
        otpw: bool,
        ot: bool,
        s2ga: bool,
        s2gb: bool,
        s2vsa: bool,
        s2vsb: bool,
        ola: bool,
        olb: bool,
        t120: bool,
        t143: bool,
        t150: bool,
        t157: bool,
        _0: u4,
        cs_actual: u5,
        _1: u9,
        steath: bool,
        stst: bool,
    },
    PWMCONF: u32,
    PWM_SCALE: u32,
    PWM_AUTO: packed struct(u32) {
        ofs: u8,
        _0: u8,
        grad: u8,
        _1: u8,
    },

    pub fn init(reg: Register, v: u32) Self {
        return switch (reg) {
            inline else => |r| @unionInit(Self, @tagName(r), @bitCast(v)),
        };
    }

    pub fn register(self: Self) Register {
        return std.meta.activeTag(self);
    }

    pub fn value(self: Self) u32 {
        return switch (self) {
            inline else => |d| @as(u32, @bitCast(d)),
        };
    }
};

pub const ReadDG = packed struct {
    comptime {
        assert(@sizeOf(ReadDG) == 4);
        assert(@offsetOf(ReadDG, "crc") == 3);
    }

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

    pub fn initRegValue(addr: u8, rv: RegValue) DataDG {
        return .init(addr, rv.register(), rv.value());
    }

    pub fn value(self: DataDG) u32 {
        return std.mem.bigToNative(u32, self.data);
    }

    pub fn regValue(self: DataDG) RegValue {
        return .init(self.reg, self.value());
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
    none: void,
    read: ReadDG,
    data: DataDG,

    pub const empty: Datagram = .{ .none = {} };

    pub fn initRead(addr: u8, reg: Register) Datagram {
        return .{ .read = .init(addr, reg) };
    }

    pub fn initWrite(addr: u8, reg: Register, data: u32) Datagram {
        return .{ .data = .init(addr, reg, data) };
    }

    pub fn checkCrc(self: *const Datagram) bool {
        return switch (self.*) {
            .none => unreachable,
            inline else => |*x| x.checkCrc(),
        };
    }

    pub fn toSlice(self: *const Datagram) []const u8 {
        return switch (self.*) {
            .none => unreachable,
            inline else => |*x| x.toSlice(),
        };
    }

    pub fn format(self: *const Datagram, w: *std.Io.Writer) std.Io.Writer.Error!void {
        return switch (self.*) {
            .none => w.print("none", .{}),
            inline else => |*x| x.format(w),
        };
    }
};

test Datagram {
    const rdg: Datagram = .initRead(0, .PWMCONF);
    try std.testing.expect(rdg.checkCrc());
    try std.testing.expectEqual(4, rdg.toSlice().len);

    const ddg: Datagram = .initWrite(0, .PWMCONF, 0xaa);
    try std.testing.expect(ddg.checkCrc());
    try std.testing.expectEqual(8, ddg.toSlice().len);
}

pub const SerialIO = struct {
    const Self = @This();

    pub const State = enum(u8) {
        IDLE,
        WRITE,
        DISCARD,
        READ,
        RETRY_WAIT,
    };

    pub const Event = union(enum) {
        data: DataDG,
        ready: void,
        data_err: void,
        crc_err: void,
        timeout: void,
    };

    const Emitter = events.Emitter(Event, 5);

    const RETRY_DELAY = time.Duration.from_ms(1);
    const TIMEOUT = time.Duration.from_ms(50);

    u: hal.uart.UART,
    state: State = .IDLE,
    ee: Emitter = .empty,

    tx_dg: Datagram = .empty,
    rx_dg: DataDG = undefined,

    pos: u8 = undefined,
    tries: u8 = undefined,
    delay: time.Absolute = undefined,
    timeout: time.Absolute = undefined,

    pub fn init(u: hal.uart.UART) Self {
        const self: Self = .{
            .u = u,
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
            if (!self.retry())
                self.emitAndIdle(.{ .data_err = {} });
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
        self.tx_dg = dg;
        self.tries = 5;
        const now = hal.time.get_time_since_boot();
        self.timeout = now.add_duration(TIMEOUT);
        self.goState(.WRITE);
    }

    fn goState(self: *Self, state: State) void {
        self.state = state;
        self.pos = 0;
    }

    fn retry(self: *Self) bool {
        if (self.tries == 0)
            return false;
        self.tries -= 1;
        const now = hal.time.get_time_since_boot();
        self.delay = now.add_duration(RETRY_DELAY);
        self.goState(.RETRY_WAIT);
        return true;
    }

    pub fn poll(self: *Self) void {
        const now = hal.time.get_time_since_boot();

        if (self.state != .IDLE and self.timeout.is_reached_by(now)) {
            self.emitAndIdle(.{ .timeout = {} });
            return;
        }

        switch (self.state) {
            .IDLE => {},
            .WRITE => {
                self.writeNonBlocking();
                if (self.pos == self.tx_dg.toSlice().len)
                    self.goState(.DISCARD);
            },
            .DISCARD => {
                self.discardNonBlocking() catch return;
                if (self.pos == self.tx_dg.toSlice().len) {
                    if (self.tx_dg == .data)
                        self.emitAndIdle(.{ .ready = {} })
                    else
                        self.goState(.READ);
                }
            },
            .READ => {
                self.readNonBlocking() catch return;
                const dg = self.rx_dg;
                if (self.pos == dg.toSlice().len) {
                    if (dg.checkCrc())
                        self.emitAndIdle(.{ .data = dg })
                    else if (!self.retry())
                        self.emitAndIdle(.{ .crc_err = {} });
                }
            },
            .RETRY_WAIT => {
                if (self.delay.is_reached_by(now))
                    self.goState(.WRITE);
            },
        }
    }
};
