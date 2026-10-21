const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;
const time = hal.time;

const logging = @import("runtime/logging.zig");
const sched = @import("runtime/scheduler.zig");
const Blinker = @import("drivers/Blinker.zig");
const switchset = @import("drivers/switchset.zig");

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
};

const SwitchMap = enum(u8) { RED, YEL, BLU, BLK };
const Switches = switchset.SwitcheSet(SwitchMap, 3);

const Scheduler = sched.makeScheduler(8);

fn onSwitch(ctx: *anyopaque, payload: Switches.SwitchEvent) !void {
    _ = ctx;
    std.log.info("{s} {any}", .{ @tagName(payload.which), payload.state });
}
pub fn main() !void {
    logging.init(.{});
    std.log.info("Starting...", .{});
    const pins = pin_config.apply();
    var scheduler: Scheduler = .empty;

    var led = Blinker.init(pins.led, 500_000);
    led.schedule(scheduler.pri(0));
    var red_led = Blinker.init(pins.red_led, 100_000);
    red_led.schedule(scheduler.pri(1));
    var yel_led = Blinker.init(pins.yel_led, 110_000);
    yel_led.schedule(scheduler.pri(2));
    var blu_led = Blinker.init(pins.blu_led, 120_000);
    blu_led.schedule(scheduler.pri(3));
    var blk_led = Blinker.init(pins.blk_led, 130_000);
    blk_led.schedule(scheduler.pri(4));

    var switches: Switches = .init(.{ pins.red_sw, pins.yel_sw, pins.blu_sw, pins.blk_sw });
    switches.addListener(.RED, onSwitch, &.{});
    switches.addListener(.YEL, onSwitch, &.{});
    switches.addListener(.BLU, onSwitch, &.{});
    switches.addListener(.BLK, onSwitch, &.{});
    switches.schedule(scheduler.pri(5));

    while (true) {
        _ = try scheduler.poll(time.get_time_since_boot());
    }
}
