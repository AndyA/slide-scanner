const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;
const time = microzig.drivers.time;

const assert = std.debug.assert;

const events = @import("../runtime/events.zig");
const sched = @import("../runtime/scheduler.zig");

const TMC2209 = @import("../drivers/TMC2209.zig");

const SerialEngine = @import("SerialEngine.zig");
const Task = @import("tasks.zig").Task;

const Datagram = TMC2209.Datagram;

const Self = @This();

pub const AppConfig = struct {
    stepper_addr: u2 = 0,
    uart: hal.uart.UART,
    stepper_config: TMC2209.Stepper.Config,
};

const FastScheduler = sched.makeScheduler(8);
const SlowScheduler = sched.makeNestedScheduler(8, 250);

const PERIODIC: []const TMC2209.Register = &.{ .GSTAT, .IOIN, .SG_RESULT };

const Periodic = blk: {
    var names: [PERIODIC.len][]const u8 = undefined;
    var types: [PERIODIC.len]type = undefined;
    var attrs: [PERIODIC.len]std.lang.Type.Struct.FieldAttributes = undefined;

    for (PERIODIC, &names, &types, &attrs) |reg, *n, *t, *a| {
        const RegType = TMC2209.RegValue.RegType(reg);
        const FieldType = struct {
            current: ?RegType = null,
            ee: events.Emitter(RegType, 3) = .empty,
            fn update(self: *@This(), value: u32) !void {
                if (self.current) |cur|
                    if (@as(u32, @bitCast(cur)) == value)
                        return;

                const nv: RegType = @bitCast(value);
                // std.log.debug("update {s}: {any}", .{ @tagName(reg), nv });
                self.current = nv;
                try self.ee.emit(nv);
            }
        };
        n.* = @tagName(reg);
        t.* = FieldType;
        a.* = .{ .default_value_ptr = &@as(FieldType, .{}) };
    }

    break :blk @Struct(.auto, null, &names, &types, &attrs);
};

const SerialState = enum { INIT_CONFIG, INIT_STATUS, READY };

config: AppConfig,
serial_state: SerialState = .INIT_CONFIG,
root_scheduler: FastScheduler = .empty,
slow_scheduler: SlowScheduler = .empty,
ser: SerialEngine,
stepper: TMC2209.Stepper,
periodic: Periodic = .{},
task: ?Task = null,

pub fn init(config: AppConfig) Self {
    return .{
        .config = config,
        .ser = .init(config.uart),
        .stepper = .init(config.stepper_config),
    };
}

fn serialErrorHandler(ctx: *anyopaque, ev: TMC2209.SerialIO.Event) !void {
    _ = ctx;
    switch (ev) {
        .data, .ready => {},
        else => std.log.err("Serial error: {any}", .{ev}),
    }
}

fn sendSetupCommands(self: *Self) void {
    const addr = self.config.stepper_addr;
    const cmds: []const Datagram = &.{
        Datagram.initWrite(addr, .{ .GCONF = .{
            .i_scale_analog = true,
            .pdn_disable = true,
            .mstep_reg_select = true,
            .shaft = false,
        } }),
        Datagram.initWrite(addr, .{ .CHOPCONF = .{
            .toff = 3,
            .h_strt = 5,
            .h_end = 0,
            .tbl = 2,
            .vsense_high = false,
            .mres = 4,
            .intpol = true,
            .dedge = false,
            .diss2g = false,
            .diss2vs = false,
        } }),
        Datagram.initWrite(addr, .{ .NODECONF = .{ .send_delay = 0 } }),
        Datagram.initWrite(addr, .{ .VACTUAL = .{ .speed = 0 } }),
    };
    for (cmds) |cmd| {
        if (self.ser.enqueue(cmd)) |ee| {
            ee.addListener(serialErrorHandler, self);
        } else unreachable;
    }
}

fn serialEvent(ctx: *anyopaque) !void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    // std.log.debug("serial engine idle ({s})", .{@tagName(self.serial_state)});

    inline for (PERIODIC) |reg| {
        const shim = struct {
            fn handler(cx: *anyopaque, ev: TMC2209.SerialIO.Event) !void {
                const me: *Self = @ptrCast(@alignCast(cx));
                switch (ev) {
                    .data => |d| {
                        var slot = &@field(me.periodic, @tagName(reg));
                        try slot.update(d.value().value());
                    },
                    .ready => unreachable,
                    else => {},
                }
            }
        };
        if (self.ser.enqueue(Datagram.initRead(self.config.stepper_addr, reg))) |ee| {
            ee.addListener(shim.handler, self);
            ee.addListener(serialErrorHandler, self);
        } else unreachable;
    }

    switch (self.serial_state) {
        .INIT_CONFIG => self.serial_state = .INIT_STATUS,
        .INIT_STATUS => {
            self.serial_state = .READY;
            self.ready();
        },
        .READY => {},
    }
}

fn ready(self: *Self) void {
    std.log.info("App ready ({any})", .{self.periodic});
    self.runTask(.tester);
}

pub fn runTask(self: *Self, id: Task.ID) void {
    self.task = Task.init(id, self);
    self.task.?.start(self);
}

pub fn exitTask(self: *Self, status: []const u8) void {
    if (self.task) |*t| {
        std.log.info("{s} {s}", .{ @tagName(t.*), status });
        t.stop(self);
        self.task = null;
    } else unreachable;
}

fn installHandlers(self: *Self) void {
    self.ser.ee.addListener(serialEvent, self);
}

fn scheduleTasks(self: *Self) !void {
    try self.stepper.start(self.root_scheduler.pri(0));
    self.ser.schedule(self.root_scheduler.pri(1));
}

pub fn start(self: *Self) !void {
    self.slow_scheduler.schedule(self.root_scheduler.pri(-1));
    self.installHandlers();
    self.sendSetupCommands();
    try self.scheduleTasks();

    while (true) {
        _ = try self.root_scheduler.poll(hal.time.get_time_since_boot());
    }
}
