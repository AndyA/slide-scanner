const std = @import("std");
const assert = std.debug.assert;
const App = @import("../App.zig");
const TMC2009 = @import("../../drivers/TMC2209.zig");

const Self = @This();

const State = enum { F, R };

app: *App,
state: State = undefined,
count: u8 = 5,

pub fn init(app: *App) Self {
    return .{ .app = app };
}

pub fn start(self: *Self, app: *App) void {
    std.log.info("test start", .{});

    app.stepper.state_ee.addListener(stepperEvent, self);

    app.stepper.setSpeed(200 * 16);
    self.goState(.F);
}

fn goState(self: *Self, state: State) void {
    switch (state) {
        .F => self.app.stepper.setRemaining(1000 * 16),
        .R => self.app.stepper.setRemaining(-1000 * 16),
    }
    self.state = state;
    std.log.info("tester state: {s}", .{@tagName(state)});
}

fn stepperEvent(ctx: *anyopaque, e: TMC2009.Stepper.Event) !void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    switch (e.state) {
        .IDLE => {
            assert(self.count != 0);
            self.count -= 1;
            if (self.count == 0) {
                self.app.exitTask("Tested");
                return;
            }
            switch (self.state) {
                .F => self.goState(.R),
                .R => self.goState(.F),
            }
        },
        else => {},
    }
}

pub fn stop(self: *Self, app: *App) void {
    std.log.info("test stop", .{});
    app.stepper.state_ee.removeListener(stepperEvent, self);
}
