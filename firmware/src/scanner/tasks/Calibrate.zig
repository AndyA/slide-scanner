const std = @import("std");
const assert = std.debug.assert;
const App = @import("../App.zig");
const TMC2009 = @import("../../drivers/TMC2209.zig");

const Self = @This();
const State = enum {
    INIT,
    WITHDRAW,
    ADVANCE,
    BACKLASH,
    RETRACT,
    STROKE,
    PARK,
};

const OptoFudge = 5 * 16;

app: *App,
state: State = .INIT,

backlash: i64 = undefined,
range: i64 = undefined,

pub fn init(app: *App) Self {
    return .{ .app = app };
}

pub fn start(self: *Self, app: *App) void {
    app.stepper.state_ee.addListener(stepperEvent, self);
    app.stepper.rt_ee.addListener(stepperRTEvent, self);

    app.stepper.setSpeed(200 * 16);

    const opto = app.config.opto_pin.read();
    std.log.info("calibrate start (opto = {d})", .{opto});
    self.goState(if (opto == 1) .WITHDRAW else .ADVANCE);
    // app.exitTask("Calibrated");
}

pub fn stop(self: *Self, app: *App) void {
    std.log.info("calibrate stop", .{});
    app.stepper.setSpeed(0);
    app.stepper.state_ee.removeListener(stepperEvent, self);
    app.stepper.rt_ee.removeListener(stepperRTEvent, self);
}

fn goState(self: *Self, state: State) void {
    std.log.info("calib state {s}", .{@tagName(state)});
    const steps = switch (state) {
        .WITHDRAW, .BACKLASH => -100 * 16,
        .ADVANCE, .STROKE => 320 * 16,
        .RETRACT => -310 * 16,
        .PARK => -self.range,
        else => 0,
    };
    self.app.stepper.setRemaining(steps);
    self.state = state;
}

fn stepperEvent(ctx: *anyopaque, e: TMC2009.Stepper.Event) !void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    std.log.info("motor: {s}", .{@tagName(e.state)});
    switch (e.state) {
        .IDLE => {
            switch (self.state) {
                .WITHDRAW => {
                    const opto = self.app.config.opto_pin.read();
                    if (opto == 1)
                        self.app.exitTask("Aperture blocked")
                    else
                        self.goState(.ADVANCE);
                },
                .RETRACT => {
                    self.app.stepper.reZero();
                    self.goState(.STROKE);
                },
                .PARK => {
                    self.app.exitTask("Calibration complete");
                },
                else => {},
            }
        },
        else => {},
    }
}

fn stepperRTEvent(ctx: *anyopaque, e: TMC2009.Stepper.RTEvent) !void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    _ = e;
    const opto = self.app.config.opto_pin.read();
    switch (self.state) {
        .ADVANCE => {
            if (opto == 1) {
                self.app.stepper.setRemaining(OptoFudge);
                self.backlash = self.app.stepper.current_position;
                self.goState(.BACKLASH);
                std.log.info("backlash start {d}", .{self.backlash});
            }
        },
        .BACKLASH => {
            if (opto == 0) {
                self.app.stepper.setRemaining(0);
                self.backlash -= -self.app.stepper.current_position;
                self.goState(.RETRACT);
                std.log.info("backlash {d}", .{self.backlash});
            }
        },
        .STROKE => {
            if (opto == 1) {
                self.app.stepper.setRemaining(OptoFudge);
                self.range = self.app.stepper.current_position;
                self.goState(.PARK);
                std.log.info("range {d}", .{self.range});
            }
        },
        else => {},
    }
    // std.log.info("motor: {s}", .{@tagName(e.state)});
}
