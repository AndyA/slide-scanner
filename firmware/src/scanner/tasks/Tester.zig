const std = @import("std");
const App = @import("../App.zig");
const TMC2009 = @import("../../drivers/TMC2209.zig");

const Self = @This();

app: *App,

pub fn init(app: *App) Self {
    return .{ .app = app };
}

pub fn start(self: *Self, app: *App) void {
    std.log.info("test start", .{});

    app.stepper.state_ee.addListener(stepperEvent, self);

    app.stepper.setSpeed(200 * 16);
    app.stepper.setRemaining(5_000 * 16);
}

fn stepperEvent(ctx: *anyopaque, e: TMC2009.Stepper.Event) !void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    std.log.info("stepper event {any}", .{e.state});
    switch (e.state) {
        .IDLE => self.app.exitTask("Test done"),
        else => {},
    }
}

pub fn stop(self: *Self, app: *App) void {
    std.log.info("test stop", .{});
    app.stepper.state_ee.removeListener(stepperEvent, self);
}
