const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;
const time = microzig.drivers.time;

const assert = std.debug.assert;

const logging = @import("runtime/logging.zig");
const sched = @import("runtime/scheduler.zig");
const Blinker = @import("drivers/Blinker.zig");
const switchset = @import("drivers/switchset.zig");

const TMC2209 = @import("drivers/TMC2209.zig");

pub const std_options = microzig.std_options(.{
    .log_level = .debug,
    .logFn = hal.uart.log,
});

comptime {
    _ = microzig.export_startup();
}

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    std.log.err("panic: {s}", .{message});
    @breakpoint();
    while (true) {}
}

const Pin = hal.gpio.Pin;

// Compile-time pin configuration
const pin_config = hal.pins.GlobalConfiguration{
    .GPIO2 = .{ .name = "red_led", .direction = .out },
    .GPIO3 = .{ .name = "red_sw", .direction = .in, .pull = .up },
    .GPIO4 = .{ .name = "yel_led", .direction = .out },
    .GPIO5 = .{ .name = "yel_sw", .direction = .in, .pull = .up },
    .GPIO6 = .{ .name = "blu_led", .direction = .out },
    .GPIO7 = .{ .name = "blu_sw", .direction = .in, .pull = .up },
    .GPIO8 = .{ .name = "blk_led", .direction = .out },
    .GPIO9 = .{ .name = "blk_sw", .direction = .in, .pull = .up },
    .GPIO25 = .{ .name = "led", .direction = .out },

    // Stepper
    .GPIO15 = .{ .name = "diag", .direction = .in, .pull = .up },
    .GPIO16 = .{ .name = "dir", .direction = .out },
    .GPIO17 = .{ .name = "step", .direction = .out },
    .GPIO18 = .{ .name = "mode2", .direction = .out },
    .GPIO19 = .{ .name = "mode1", .direction = .out },
    .GPIO20 = .{ .name = "pdn_tx", .direction = .out },
    .GPIO21 = .{ .name = "pdn_rx", .direction = .in },
    .GPIO22 = .{ .name = "en", .direction = .out },
};

const SwitchMap = enum(u8) { RED, YEL, BLU, BLK };
const Switches = switchset.SwitcheSet(SwitchMap, 3);

const FastScheduler = sched.makeScheduler(8);
const SlowScheduler = sched.makeNestedScheduler(8, 250);

const SwitchBox = struct {
    const Self = @This();
    pins: [4]Pin,

    fn onSwitch(ctx: *anyopaque, payload: Switches.SwitchEvent) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        std.log.info("{s} {any}", .{ @tagName(payload.which), payload.state });
        if (payload.state) {
            self.pins[@backingInt(payload.which)].toggle();
        }
    }
};

const uart = hal.uart.instance.num(1);

const SerialTask = struct {
    const Self = @This();

    const PERIOD = 500;

    sio: TMC2209.SerialIO = undefined,

    pub fn init(u: hal.uart.UART) Self {
        return .{ .sio = .init(u) };
    }

    fn reSchedule(self: *Self, slot: *sched.ScheduleSlot) void {
        const deadline = slot.now.add_duration(time.Duration.from_us(PERIOD));
        slot.schedule(deadline, task, self);
    }

    pub fn schedule(self: *Self, slot: *sched.ScheduleSlot) void {
        self.sio.ee.addListener(listener, self);
        self.reSchedule(slot);
    }

    fn task(ctx: *anyopaque, slot: *sched.ScheduleSlot) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.sio.poll();
        self.reSchedule(slot);
    }

    fn listener(ctx: *anyopaque, payload: TMC2209.SerialIO.Event) !void {
        _ = ctx;
        switch (payload) {
            .received => |dg| std.log.info("event {s}: {x}", .{ @tagName(payload), dg.value() }),
            else => std.log.info("event {s}", .{@tagName(payload)}),
        }
    }
};

pub fn main() !void {
    logging.init(.{});
    std.log.info("Starting...", .{});
    const pins = pin_config.apply();
    var root_scheduler: FastScheduler = .empty;
    var slow_scheduler: SlowScheduler = .empty;

    slow_scheduler.schedule(root_scheduler.pri(-1));

    pins.pdn_tx.set_function(.uart);
    pins.pdn_rx.set_function(.uart);

    uart.apply(.{
        .clock_config = hal.clock_config,
    });

    var ser: SerialTask = .init(uart);
    ser.schedule(root_scheduler.pri(0));

    var box: SwitchBox = .{ .pins = .{
        pins.red_led,
        pins.yel_led,
        pins.blu_led,
        pins.blk_led,
    } };
    var switches: Switches = .init(.{
        pins.red_sw,
        pins.yel_sw,
        pins.blu_sw,
        pins.blk_sw,
    });

    switches.addListener(.RED, SwitchBox.onSwitch, &box);
    switches.addListener(.YEL, SwitchBox.onSwitch, &box);
    switches.addListener(.BLU, SwitchBox.onSwitch, &box);
    switches.addListener(.BLK, SwitchBox.onSwitch, &box);
    switches.schedule(slow_scheduler.pri(0));

    var blinker: Blinker = .init(pins.led, 250_000);
    blinker.schedule(slow_scheduler.pri(1));

    ser.sio.send(TMC2209.Datagram.initRead(0, .GCONF));

    while (true) {
        _ = try root_scheduler.poll(hal.time.get_time_since_boot());
    }
}
