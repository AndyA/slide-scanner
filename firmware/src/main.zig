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

    .GPIO16 = .{ .name = "debug", .direction = .out },
    .GPIO21 = .{ .name = "dir", .direction = .out },
    .GPIO20 = .{ .name = "step", .direction = .out },
    // .GPIO19 = .{ .name = "mode1", .direction = .out },
    // .GPIO18 = .{ .name = "mode2", .direction = .out },
    // .GPIO17 = .{ .name = "fault", .direction = .in, .pull = .up },
    // .GPIO16 = .{ .name = "reset", .direction = .out },
    // .GPIO27 = .{ .name = "debug", .direction = .out },

};

const Scheduler = sched.makeScheduler(8);

pub fn main() !void {
    logging.init(.{});
    std.log.info("Starting...", .{});
    const pins = pin_config.apply();
    var scheduler: Scheduler = .empty;

    var led = Blinker.init_us(pins.led, 250_000);
    led.schedule(scheduler.pri(0));
    var pulser: Pulser = .{ .step_pin = pins.debug, .rate = 1000 };
    pulser.schedule(scheduler.pri(1));

    while (true) {
        _ = try scheduler.poll(time.get_time_since_boot());
    }
}
