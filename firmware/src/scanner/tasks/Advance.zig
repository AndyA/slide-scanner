const std = @import("std");
const assert = std.debug.assert;
const App = @import("../App.zig");
const TMC2009 = @import("../../drivers/TMC2209.zig");

const Self = @This();
const State = enum { INIT, HOME, ADVANCE };

app: *App,
state: State = .INIT,
current_opto: u1 = 0,

pub fn init(app: *App) Self {
    return .{ .app = app };
}

pub fn start(self: *Self, app: *App) void {
    app.stepper.state_ee.addListener(stepperEvent, self);
    app.stepper.rt_ee.addListener(stepperRTEvent, self);

    if (app.calibration == null) {
        app.exitTask("Not calibrated");
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
    // std.log.info("calib state {s}", .{@tagName(state)});
    const steps = switch (state) {
        .HOME => -self.app.stepper.current_position,
        .ADVANCE => self.app.calibration.?.range + 800,
        else => 0,
    };
    self.app.stepper.setRemaining(steps);
    self.state = state;
}

fn stepperEvent(ctx: *anyopaque, e: TMC2009.Stepper.Event) !void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    std.log.info("motor: {s} {d}", .{ @tagName(e.state), self.app.stepper.current_position });
    switch (e.state) {
        .IDLE => {
            switch (self.state) {
                .INIT => unreachable,
                .HOME => self.goState(.ADVANCE),
                else => {},
            }
        },
        else => {},
    }
}

fn stepperRTEvent(ctx: *anyopaque, _: TMC2009.Stepper.RTEvent) !void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    const opto = self.app.config.opto_pin.read();
    if (opto != self.current_opto) {
        self.current_opto = opto;
        std.log.info("opto: {d}, pos: {d}", .{ opto, self.app.stepper.current_position });
    }
}
