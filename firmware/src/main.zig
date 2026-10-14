const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;
const time = hal.time;

const logging = @import("runtime/logging.zig");
const sched = @import("runtime/scheduler.zig");
const Blinker = @import("drivers/Blinker.zig");

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

// Compile-time pin configuration
const pin_config = hal.pins.GlobalConfiguration{
    .GPIO25 = .{
        .name = "led",
        .direction = .out,
    },
};

const Scheduler = sched.makeScheduler(8);

pub fn main() !void {
    logging.init(.{});
    std.log.info("Starting...", .{});
    const pins = pin_config.apply();
    var scheduler: Scheduler = .empty;

    var led = Blinker.init_us(pins.led, 250_000);
    led.schedule(scheduler.pri(0));

    while (true) {
        _ = try scheduler.poll(time.get_time_since_boot());
    }
}
