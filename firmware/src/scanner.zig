const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;
const time = microzig.drivers.time;

const assert = std.debug.assert;

const events = @import("runtime/events.zig");
const logging = @import("runtime/logging.zig");
const sched = @import("runtime/scheduler.zig");

const Blinker = @import("drivers/Blinker.zig");
const switchset = @import("drivers/switchset.zig");
const TMC2209 = @import("drivers/TMC2209.zig");

const SerialEngine = @import("scanner/SerialEngine.zig");
const App = @import("scanner/App.zig");

pub const std_options = microzig.std_options(.{
    .log_level = .debug,
    .log_scope_levels = &.{
        .{ .scope = .usb_dev, .level = .warn },
        .{ .scope = .usb_ctrl, .level = .warn },
        .{ .scope = .usb_cdc, .level = .warn },
    },
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
    .GPIO2 = .{ .name = "blk_sw", .direction = .in, .pull = .up },
    .GPIO3 = .{ .name = "blk_led", .direction = .out },
    .GPIO4 = .{ .name = "blu_sw", .direction = .in, .pull = .up },
    .GPIO5 = .{ .name = "blu_led", .direction = .out },
    .GPIO6 = .{ .name = "yel_sw", .direction = .in, .pull = .up },
    .GPIO7 = .{ .name = "yel_led", .direction = .out },
    .GPIO8 = .{ .name = "red_sw", .direction = .in, .pull = .up },
    .GPIO9 = .{ .name = "red_led", .direction = .out },
    .GPIO25 = .{ .name = "led", .direction = .out },

    // Stepper
    .GPIO15 = .{ .name = "lim_opto", .direction = .in, .pull = .up },
    .GPIO16 = .{ .name = "dir", .direction = .out },
    .GPIO17 = .{ .name = "step", .direction = .out },
    .GPIO18 = .{ .name = "mode2", .direction = .out },
    .GPIO19 = .{ .name = "mode1", .direction = .out },
    .GPIO20 = .{ .name = "pdn_tx", .direction = .out },
    .GPIO21 = .{ .name = "pdn_rx", .direction = .in },
    .GPIO22 = .{ .name = "en", .direction = .out },
};

pub fn main() !void {
    logging.init(.{});
    std.log.info("Starting...", .{});
    const pins = pin_config.apply();

    pins.pdn_tx.set_function(.uart);
    pins.pdn_rx.set_function(.uart);

    const uart = hal.uart.instance.num(1);
    var app: App = .init(.{
        .uart = uart,
        .stepper_config = .{
            .step_pin = pins.step,
            .dir_pin = pins.dir,
        },
        .opto_pin = pins.lim_opto,
        .task_switches = .{
            pins.blk_sw,
            pins.blu_sw,
            pins.yel_sw,
            pins.red_sw,
        },
        .task_leds = .{
            pins.blk_led,
            pins.blu_led,
            pins.yel_led,
            pins.red_led,
        },
    });

    uart.apply(.{ .clock_config = hal.clock_config });

    pins.en.put(0);
    pins.mode1.put(0);
    pins.mode2.put(0);

    // app.ser.schedule(app.root_scheduler.pri(1));

    var blinker: Blinker = .init(pins.led, 100_000);
    blinker.schedule(app.slow_scheduler.pri(-1));

    try app.start();
}
