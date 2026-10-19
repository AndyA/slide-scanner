const std = @import("std");
const switchset = @import("../drivers/switchset.zig");
const sched = @import("../runtime/scheduler.zig");
const STC2209 = @import("../drivers/STC2209.zig");

const Self = @This();
const SwitchMap = enum(u8) { OPTO, HALT };
const Switches = switchset.SwitcheSet(SwitchMap, 3);

pub const Config = struct {
    motor: *STC2209,
    switch_pins: Switches.PinConfig,
};

pub const Event = enum {
    MOTOR_STOP,
    LIMIT_UNKNOWN,
    LIMIT_ARRIVED,
    LIMIT_LEFT,
    HALT,
};

pub const State = enum {
    IDLE,
    ADVANCE,
    RETREAT,
};

config: Config = undefined,
switches: Switches = undefined,
state: State = .IDLE,
last_opto_event: Event = .LIMIT_UNKNOWN,

pub fn init(config: Config) Self {
    return .{
        .config = config,
        .switches = .init(config.switch_pins),
    };
}

fn onEvent(self: *Self, event: Event) void {
    std.log.info("s: {s}, e: {s}", .{ @tagName(self.state), @tagName(event) });
    const m = self.config.motor;
    switch (self.state) {
        .IDLE => switch (self.last_opto_event) {
            .LIMIT_LEFT => {
                m.setRemaining(10000);
                m.setSpeed(5000);
                self.state = .ADVANCE;
            },
            else => {},
        },
        .ADVANCE => switch (event) {
            .LIMIT_ARRIVED => {
                m.setRemaining(-5150);
                m.setSpeed(5000);
                self.state = .RETREAT;
            },
            else => {},
        },
        .RETREAT => switch (event) {
            .MOTOR_STOP => {
                m.setRemaining(10000);
                m.setSpeed(5000);
                self.state = .ADVANCE;
            },
            else => {},
        },
        // else => {
        //     std.log.info("UNHANDLED s: {s}, e: {s}", .{ @tagName(self.state), @tagName(event) });
        // },
    }
}

fn onHaltSwitch(ctx: *anyopaque, payload: Switches.SwitchEvent) !void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    if (payload.state) self.onEvent(.HALT);
}

fn onOpto(ctx: *anyopaque, payload: Switches.SwitchEvent) !void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    const event: Event = if (payload.state) .LIMIT_LEFT else .LIMIT_ARRIVED;
    self.last_opto_event = event;
    self.onEvent(event);
}

fn onMotor(ctx: *anyopaque, e: STC2209.EventPayload) !void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    std.log.info("{s}", .{@tagName(e.state)});
    switch (e.state) {
        .IDLE => self.onEvent(.MOTOR_STOP),
        else => {},
    }
}

pub fn schedule(
    self: *Self,
    motor_slot: *sched.ScheduleSlot,
    switch_slot: *sched.ScheduleSlot,
) !void {
    self.switches.addListener(.HALT, onHaltSwitch, self);
    self.switches.addListener(.OPTO, onOpto, self);

    const m = self.config.motor;
    m.state_ee.addListener(onMotor, self);

    self.switches.schedule(switch_slot);
    try self.config.motor.start(motor_slot);
    m.setSpeed(5000);
}
