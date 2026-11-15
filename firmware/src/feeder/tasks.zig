const App = @import("App.zig");

pub const Task = union(enum) {
    const Self = @This();
    pub const ID = @typeInfo(Self).@"union".tag_type.?;

    calibrate: @import("tasks/Calibrate.zig"),
    advance: @import("tasks/Advance.zig"),

    pub fn init(id: ID, app: *App) Self {
        switch (id) {
            inline else => |ii| {
                const Type = @typeInfo(Self).@"union".field_types[@backingInt(ii)];
                const task: Type = if (@hasDecl(Type, "init")) .init(app) else .{};
                return @unionInit(Self, @tagName(ii), task);
            },
        }
    }

    pub fn start(self: *Self, app: *App) void {
        switch (self.*) {
            inline else => |*x| x.start(app),
        }
    }

    pub fn stop(self: *Self, app: *App) void {
        switch (self.*) {
            inline else => |*x| x.stop(app),
        }
    }
};
