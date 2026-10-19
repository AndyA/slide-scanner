const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;
const time = hal.time;

const logging = @import("runtime/logging.zig");
const sched = @import("runtime/scheduler.zig");
const Blinker = @import("drivers/Blinker.zig");
const STC2209 = @import("drivers/STC2209.zig");

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

const Pulser = struct {
    const Self = @This();
    step_pin: Pin,
    rate: u64,
    state: enum { off, on } = .off,

    pub fn schedule(self: *Self, slot: *sched.ScheduleSlot) void {
        slot.schedule(slot.now, advance, self);
    }

    fn advance(ctx: *anyopaque, slot: *sched.ScheduleSlot) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        switch (self.state) {
            .off => {
                self.step_pin.put(1);
                slot.delay(self.rate);
                self.state = .on;
            },
            .on => {
                self.step_pin.put(0);
                slot.delay(self.rate);
                self.state = .off;
            },
        }
    }
};

// Compile-time pin configuration
const pin_config = hal.pins.GlobalConfiguration{
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
    try motor.start(scheduler.pri(0));

    motor.setSpeed(2000);
    motor.rotate(1000000);

    var led = Blinker.init(pins.led, 500_000);
    led.schedule(scheduler.pri(1));

    while (true) {
        _ = try scheduler.poll(time.get_time_since_boot());
        led.setDelay(if (pins.diag.read() == 1) 50_000 else 500_000);
    }
}
