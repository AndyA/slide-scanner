const std = @import("std");
const App = @import("../App.zig");

const Self = @This();

pub fn start(self: *Self, app: *App) void {
    _ = self;
    std.log.info("calibrate start", .{});
    app.exitTask("Calibrated");
}

pub fn stop(self: *Self, app: *App) void {
    std.log.info("calibrate stop", .{});
    _ = self;
    _ = app;
}
