const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;
const time = hal.time;

const logging = @import("runtime/logging.zig");
const sched = @import("runtime/scheduler.zig");
const Blinker = @import("drivers/Blinker.zig");
const STC2209 = @import("drivers/STC2209.zig");
const Engine = @import("scanner/Engine.zig");

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
    .GPIO4 = .{ .name = "opto", .direction = .in, .pull = .up },
    .GPIO8 = .{ .name = "hlt_sw", .direction = .in, .pull = .up },
    .GPIO9 = .{ .name = "rst_led", .direction = .out },
    .GPIO13 = .{ .name = "hlt_led", .direction = .out },
    .GPIO25 = .{ .name = "led", .direction = .out },

    // STC2209
    .GPIO15 = .{ .name = "diag", .direction = .in, .pull = .up },
    .GPIO16 = .{ .name = "dir", .direction = .out },
    .GPIO17 = .{ .name = "step", .direction = .out },
    .GPIO18 = .{ .name = "mode2", .direction = .out },
    .GPIO19 = .{ .name = "mode1", .direction = .out },
    .GPIO20 = .{ .name = "pdn_tx", .direction = .out },
    .GPIO21 = .{ .name = "pdn_rx", .direction = .out },
    .GPIO22 = .{ .name = "en", .direction = .out },
};

const Scheduler = sched.makeScheduler(8);

pub fn main() !void {
    logging.init(.{});
    std.log.info("Starting...", .{});
    const pins = pin_config.apply();
    var scheduler: Scheduler = .empty;

    pins.pdn_rx.put(1);
    pins.pdn_tx.put(1);

    var motor: STC2209 = .init(.{
        .step_pin = pins.step,
        .dir_pin = pins.dir,
        .enable_pin = pins.en,
        .mode1_pin = pins.mode1,
        .mode2_pin = pins.mode2,
    });

    var led = Blinker.init(pins.led, 500_000);
    led.schedule(scheduler.pri(1));
    var rst_led = Blinker.init(pins.rst_led, 300_000);
    rst_led.schedule(scheduler.pri(2));
    var hlt_led = Blinker.init(pins.hlt_led, 100_000);
    hlt_led.schedule(scheduler.pri(3));

    var engine: Engine = .init(.{
        .motor = &motor,
        .switch_pins = .{ pins.opto, pins.hlt_sw },
    });
    try engine.schedule(scheduler.pri(0), scheduler.pri(4));

    while (true) {
        _ = try scheduler.poll(time.get_time_since_boot());
    }
}
