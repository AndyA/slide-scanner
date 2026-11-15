const std = @import("std");
const assert = std.debug.assert;
const App = @import("../App.zig");
const TMC2009 = @import("../../drivers/TMC2209.zig");

const Self = @This();
const State = enum { INIT, HOME, ADVANCE, RETREAT, EMPTY, ERROR };

app: *App,
state: State = .INIT,
notch: bool = false,

pub fn init(app: *App) Self {
    return .{ .app = app };
}

pub fn start(self: *Self, app: *App) void {
    app.stepper.state_ee.addListener(stepperEvent, self);
    app.stepper.rt_ee.addListener(stepperRTEvent, self);

    if (app.calibration == null) {
        app.exitTask(.NotCalibrated);
        return;
    }

    app.stepper.setSpeed(200 * 16);
    if (app.stepper.current_position == 0)
        self.goState(.ADVANCE)
    else
        self.goState(.HOME);
}

pub fn stop(self: *Self, app: *App) void {
    app.stepper.setSpeed(0);
    app.stepper.state_ee.removeListener(stepperEvent, self);
    app.stepper.rt_ee.removeListener(stepperRTEvent, self);
}

fn goState(self: *Self, state: State) void {
    const steps = switch (state) {
        .INIT => unreachable,
        .HOME, .EMPTY, .ERROR, .RETREAT => -self.app.stepper.current_position,
        .ADVANCE => self.app.calibration.?.range + 800,
    };
    self.app.stepper.setRemaining(steps);
    self.state = state;
}

fn stepperEvent(ctx: *anyopaque, e: TMC2009.Stepper.Event) !void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    switch (e.state) {
        .IDLE => {
            switch (self.state) {
                .INIT => unreachable,
                .HOME => self.goState(.ADVANCE),
                .EMPTY => self.app.exitTask(.AdvanceEmpty),
                .ERROR => self.app.exitTask(.AdvanceError),
                .ADVANCE => self.goState(.RETREAT),
                .RETREAT => self.app.exitTask(if (self.notch) .AdvanceBlank else .AdvanceSlide),
            }
        },
        else => {},
    }
}

fn stepperRTEvent(ctx: *anyopaque, _: TMC2009.Stepper.RTEvent) !void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    switch (self.state) {
        .ADVANCE => {
            const opto = self.app.config.opto_pin.read();
            switch (self.app.stepper.current_position) {
                1850 => if (opto == 0) self.goState(.EMPTY),
                3000 => self.notch = opto == 0,
                4150 => if (opto == 0) self.goState(.ERROR),
                else => {},
            }
        },
        else => {},
    }
}
