const std = @import("std");
const App = @import("../App.zig");

const Self = @This();

app: App,

pub fn init(app: *App) Self {
    return .{ .app = app };
}

pub fn start(self: *Self) void {
    _ = self;
}

pub fn stop(self: *Self) void {
    _ = self;
}
