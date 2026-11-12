const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const microzig = @import("microzig");
const hal = microzig.hal;
const time = microzig.drivers.time;

const ScheduleSlot = @import("../runtime/scheduler.zig").ScheduleSlot;
const events = @import("../runtime/events.zig");

const Pin = hal.gpio.Pin;

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
    GSTAT = 0x01, // R/WC
    IFCNT = 0x02, // R
    NODECONF = 0x03, // W
    OTP_PROG = 0x04, // W
    OTP_READ = 0x05, // R
    IOIN = 0x06, // R
    FACTORY_CONF = 0x07, // R/W
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
    CHOPCONF = 0x6C, // R/W
    DRV_STATUS = 0x6F, // R
    PWMCONF = 0x70, // R/W
    PWM_SCALE = 0x71, // R
    PWM_AUTO = 0x72, // R
};

pub const RegValue = union(Register) {
    const Self = @This();

    GCONF: packed struct(u32) { // R/W
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
    GSTAT: packed struct(u32) { // R/WC
        reset: bool = false,
        drv_err: bool = false,
        uv_cp: bool = false,
        _0: u29 = 0,
    },
    IFCNT: packed struct(u32) { // R
        count: u8,
        _0: u24,
    },
    NODECONF: packed struct(u32) { // W
        _0: u8 = 0,
        send_delay: u4,
        _1: u20 = 0,
    },
    OTP_PROG: packed struct(u32) { // W
        bit: u3,
        byte: u2,
        _0: u3 = 0,
        magic: u8 = 0xbd,
        _1: u16 = 0,
    },
    OTP_READ: packed struct(u32) { // R
        otp0: packed struct(u8) {
            f_clk_trim: u5,
            ot_trim: u1,
            internal_rsense: bool,
            tbl: u1,
        },
        otp1: packed struct(u8) {
            pwm_grad: u4,
            pwm_autograd: bool,
            tpwm_thrs: u3,
        },
        otp2: packed struct(u8) {
            pwm_ofs: bool,
            pwm_reg: bool,
            pwm_freq: bool,
            i_hold_delay: u2,
            i_hold: u2,
            en_spreadcycle: bool,
        },
        _0: u8 = 0,
    },
    IOIN: packed struct(u32) { // R
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
    FACTORY_CONF: packed struct(u32) { // R/W
        fclk_trim: u5,
        _0: u3 = 0,
        ot_trim: u2,
        _1: u22 = 0,
    },
    IHOLD_IRUN: packed struct(u32) { // W
        hold: u5,
        _0: u3 = 0,
        run: u5,
        _1: u3 = 0,
        hold_delay: u4,
        _2: u12 = 0,
    },
    TPOWERDOWN: packed struct(u32) { //W
        time: u8,
        _0: u24 = 0,
    },
    TSTEP: packed struct(u32) { // R
        step: u20,
        _0: u12,
    },
    TPWMTHRS: packed struct(u32) { // W
        threshold: u20,
        _0: u12,
    },
    TCOOLTHRS: packed struct(u32) { // W
        threshold: u20,
        _0: u12,
    },
    VACTUAL: packed struct(u32) { // W
        speed: i24,
        _0: u8 = 0,
    },
    SGTHRS: packed struct(u32) { // W
        threshold: u8,
        _0: u24 = 0,
    },
    SG_RESULT: packed struct(u32) { // R
        result: u10,
        _0: u22,
    },
    COOLCONF: packed struct(u32) { // W
        semin: u4,
        _0: u1 = 0,
        seup: u2,
        _1: u1 = 0,
        semax: u4,
        _2: u1 = 0,
        sedn: u2,
        seimin: u1,
        _3: u16 = 0,
    },
    MSCNT: packed struct(u32) { // R
        counter: u10,
        _0: u22,
    },
    MSCURACT: packed struct(u32) { // R
        cur_b: u9,
        _0: u7,
        cur_a: u9,
        _1: u7,
    },
    CHOPCONF: packed struct(u32) { // R/W
        toff: u4,
        h_strt: u3,
        h_end: u4,
        _0: u4 = 0,
        tbl: u2,
        vsense_high: bool,
        _1: u6 = 0,
        mres: u4,
        intpol: bool,
        dedge: bool,
        diss2g: bool,
        diss2vs: bool,
    },
    DRV_STATUS: packed struct(u32) { // R
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
        stealth: bool,
        stst: bool,
    },
    PWMCONF: packed struct(u32) { // R/W
        pwm_ofs: u8,
        pwm_grad: u8,
        pwm_freq: u2,
        pwm_autoscale: bool,
        pwm_autograd: bool,
        freewheel: u2,
        _0: u2 = 0,
        pwm_reg: u4,
        pwm_lim: u4,
    },
    PWM_SCALE: packed struct(u32) { // R
        sum: u8,
        _0: u8,
        auto: u8,
        _1: u8,
    },
    PWM_AUTO: packed struct(u32) { // R
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
            inline else => |v| @as(u32, @bitCast(v)),
        };
    }

    pub fn RegType(comptime r: Register) type {
        const tag_index = blk: {
            const tag = @backingInt(r);
            const info = @typeInfo(Register).@"enum";
            for (info.field_values, 0..) |t, i|
                if (t == tag) break :blk i;
            unreachable;
        };
        return @typeInfo(Self).@"union".field_types[tag_index];
    }
};

test RegValue {
    const mscnt: RegValue.RegType(.MSCNT) = .{ .counter = 0, ._0 = 0 };
    _ = mscnt; // the test is that it compiles
}

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
            self.rawValue(),
            if (self.checkCrc()) "ok" else "bad",
        });
    }

    fn calcCrc(self: DataDG) u8 {
        return calculateCrc(self.toSlice()[0..@offsetOf(DataDG, "crc")]);
    }

    pub fn initRaw(addr: u8, reg: Register, data: u32) DataDG {
        var self: DataDG = .{
            .addr = addr,
            .reg = reg,
            .write = true,
            .data = std.mem.nativeToBig(u32, data),
        };
        self.crc = self.calcCrc();
        return self;
    }

    pub fn init(addr: u8, rv: RegValue) DataDG {
        return .initRaw(addr, rv.register(), rv.value());
    }

    pub fn rawValue(self: DataDG) u32 {
        return std.mem.bigToNative(u32, self.data);
    }

    pub fn value(self: DataDG) RegValue {
        return .init(self.reg, self.rawValue());
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
    const dg: DataDG = .initRaw(1, .FACTORY_CONF, 0x12345678);
    try std.testing.expect(dg.checkCrc());
    try std.testing.expectEqual(0x12345678, dg.rawValue());
}

pub const Datagram = union(enum) {
    none: void,
    read: ReadDG,
    data: DataDG,

    pub const empty: Datagram = .{ .none = {} };

    pub fn initRead(addr: u8, reg: Register) Datagram {
        return .{ .read = .init(addr, reg) };
    }

    pub fn initWrite(addr: u8, rv: RegValue) Datagram {
        return .{ .data = .init(addr, rv) };
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

    const ddg: Datagram = .initWrite(0, .init(.PWMCONF, 0xaa));
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

pub const Stepper = struct {
    const Self = @This();

    // During idling we wake up every 100µS to notice whether
    // we need to do anything
    const IDLE_TIME = 100; // µS

    // We assert STEP for up to two ticks. If we used one tick we might
    // sometimes get a much shorter delay due to scheduler granularity.
    // We only actually need 100ns
    const STEP_TIME = 2; // µS
    const MODE_HOLD_TIME = 101; // µS

    pub const Config = struct {
        step_pin: Pin,
        dir_pin: Pin,
    };

    pub const State = enum(u8) {
        INIT,
        IDLE,

        START,
        MOVING,
        STEP,
        STEPPING,
        STEPPED,

        STOPPING,
    };

    pub const EventPayload = struct {
        target: *Self,
        state: State,
    };

    pub const RTEventPayload = struct {
        target: *Self,
        state: State,
        now: time.Absolute,
        running: bool,
    };

    pub const Direction = enum(u2) {
        CW,
        CCW,
        UNKNOWN, // at startup

        pub fn fromError(err: anytype) Direction {
            if (err < 0)
                return .CCW;
            if (err > 0)
                return .CW;
            return .UNKNOWN;
        }

        pub fn step(self: Direction, comptime T: type) T {
            return switch (self) {
                .CW => 1,
                .CCW => -1,
                .UNKNOWN => 0,
            };
        }
    };

    config: Config,

    state: State = .INIT,

    direction: Direction = .UNKNOWN,

    /// Current speed (steps/second)
    speed: u32 = 0,

    /// Number of steps still to perform
    steps_remaining: i64 = 0,

    /// The current position of the motor
    current_position: i64 = 0,

    /// Current per-step interval
    us_per_step: u32 = 0,

    /// Event emitter - gets notifications of significant state changes:
    ///   .INIT <=> .IDLE
    ///   .IDLE <=> .MOVING
    state_ee: events.Emitter(EventPayload, 5) = .empty,

    /// Realtime event emitter - called after every step before the delay
    /// to the next step is calculated. Event handlers can usefully vary
    /// the speed here. Only allows two subscribers because it makes no
    /// sense to have multiple parties fighting over control of the
    /// speed. Having two allows a handler to be hooked with `once` and
    /// be able to re-hook using `once` again from within the handler.
    rt_ee: events.Emitter(RTEventPayload, 2) = .empty,

    pub fn init(config: Config) Self {
        return .{ .config = config };
    }

    pub fn start(self: *Self, slot: *ScheduleSlot) !void {
        assert(self.state == .INIT);
        self.direction = .UNKNOWN;
        slot.schedule(slot.now, stateMachine, self);
        try self.notifyState(.IDLE);
    }

    pub fn stop(self: *Self) void {
        if (self.state != .INIT) {
            self.state = .STOPPING;
            self.setSpeed(0);
            self.steps_remaining = 0;
        }
    }

    pub fn rotate(self: *Self, steps: i64) void {
        self.steps_remaining += steps;
    }

    pub fn setRemaining(self: *Self, steps: i64) void {
        self.steps_remaining = steps;
    }

    pub fn setPosition(self: *Self, pos: i64) void {
        self.steps_remaining = pos - self.current_position;
    }

    pub fn reZero(self: *Self) void {
        self.current_position = 0;
    }

    pub fn setSpeed(self: *Self, speed: u32) void {
        if (speed != self.speed) {
            const us_per_step = 1_000_000 / speed;
            self.us_per_step = @max(STEP_TIME * 2, us_per_step);
            self.speed = speed;
            std.log.debug("us per step: {d}", .{self.us_per_step});
        }
    }

    fn notifyState(self: *Self, state: State) !void {
        std.log.info("{s} -> {s}", .{ @tagName(self.state), @tagName(state) });
        self.state = state;
        try self.state_ee.emit(.{ .target = self, .state = state });
    }

    fn rtNotify(self: *Self, now: time.Absolute, running: bool) !void {
        try self.rt_ee.emit(.{
            .target = self,
            .state = self.state,
            .now = now,
            .running = running,
        });
    }

    fn stateMachine(ctx: *anyopaque, slot: *ScheduleSlot) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const c = self.config;

        sm: switch (self.state) {
            .INIT => unreachable,
            .IDLE => {
                // Keep the RT notifications coming
                try self.rtNotify(slot.now, false);

                if (self.steps_remaining != 0) {
                    try self.notifyState(.START);
                    continue :sm self.state;
                }

                slot.delay(IDLE_TIME);
            },

            .START => {
                self.direction = .UNKNOWN;
                self.state = .MOVING;
                continue :sm self.state;
            },
            .MOVING => {
                if (self.steps_remaining == 0) {
                    try self.notifyState(.IDLE);
                    continue :sm self.state;
                }

                self.state = .STEP;

                const new_direction: Direction = .fromError(self.steps_remaining);
                if (new_direction == self.direction)
                    continue :sm self.state; // all set, go and step

                self.direction = new_direction;

                c.dir_pin.put(switch (new_direction) {
                    .CW => 1,
                    .CCW => 0,
                    else => unreachable,
                });

                slot.delay(STEP_TIME); // allow dir to settle
            },
            .STEP => {
                if (self.steps_remaining == 0) {
                    try self.notifyState(.IDLE);
                    continue :sm self.state;
                }

                if (self.speed == 0) {
                    // Loop while we wait for non-zero speed
                    try self.rtNotify(slot.now, true);
                    self.state = .MOVING;
                    slot.delay(IDLE_TIME);
                } else {
                    c.step_pin.put(1);
                    self.state = .STEPPING;
                    slot.delay(STEP_TIME);
                }
            },
            .STEPPING => {
                c.step_pin.put(0);

                // Update state as if the step was already complete.
                const delta: i32 = if (self.steps_remaining > 0) 1 else -1;

                self.current_position += delta;
                self.steps_remaining -= delta;

                // Send the RT notification during our long wait to give it the
                // best chance of completing without affecting our step timing.
                try self.rtNotify(slot.now, true);

                // Set the delay after sending the RT notification in case the
                // RT handler changes speed, updating us_per_step.
                slot.delay(self.us_per_step - STEP_TIME);

                self.state = .STEPPED;
            },
            .STEPPED => {
                if (self.steps_remaining == 0)
                    try self.notifyState(.IDLE)
                else
                    self.state = .MOVING;

                continue :sm self.state;
            },

            .STOPPING => {
                try self.notifyState(.INIT);
                // don't reschedule
            },
        }
    }
};
