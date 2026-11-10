const std = @import("std");
const assert = std.debug.assert;

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
    TSTEP: u32,
    TPWMTHRS: u32,
    TCOOLTHRS: u32,
    VACTUAL: i32,
    SGTHRS: u32,
    SG_RESULT: u32,
    COOLCONF: u32,
    MSCNT: u32,
    MSCURACT: u32,
    CHOPCONF: u32,
    DRV_STATUS: u32,
    PWMCONF: u32,
    PWM_SCALE: u32,
    PWM_AUTO: u32,

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

pub fn main() void {
    const f1: RegValue = .{ .GCONF = .{} };
    std.debug.print(
        "f1 {any} 0x{x:0>2} 0x{x:0>8}\n",
        .{ f1, @backingInt(f1.register()), f1.value() },
    );
    const f2: RegValue = .init(.GCONF, 0x3ff);
    std.debug.print("f2 {any}\n", .{f2});
    const f3: RegValue = .{ .VACTUAL = -1000 };
    std.debug.print("f3 {any}\n", .{f3});
    const f4: RegValue = .init(.IOIN, 0x210003ff);
    std.debug.print("f2 {any}\n", .{f4});
}

test {
    _ = @import("runtime/events.zig");
    _ = @import("runtime/tools.zig");
    _ = @import("runtime/promise.zig");
    _ = @import("drivers/TMC2209.zig");
}
