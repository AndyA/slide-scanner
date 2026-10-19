const std = @import("std");
const microzig = @import("microzig");
const time = microzig.drivers.time;
const Pin = microzig.hal.gpio.Pin;

const sched = @import("../runtime/scheduler.zig");
const events = @import("../runtime/events.zig");
const tools = @import("../runtime/tools.zig");

const POLL_DELAY = 1000;
const DEBOUNCE = 30;

pub fn SwitcheSet(comptime SwitchMap: type, max_listeners: u8) type {
    const count = tools.enumSize(SwitchMap);
    return struct {
        const Self = @This();

        pub const SwitchEvent = struct {
            which: SwitchMap,
            state: bool,
        };

        const Emitter = events.Emitter(SwitchEvent, max_listeners);

        pub const Switch = struct {
            pin: Pin,
            state: bool = false,
            ee: Emitter = .empty,

            last_state: bool = false,
            time_in_state: u8 = 0,

            fn poll(self: *Switch, which: SwitchMap) !void {
                const next_state = self.pin.read() == 0;
                if (next_state == self.last_state) {
                    self.time_in_state += 1;
                    if (self.time_in_state == DEBOUNCE) {
                        self.time_in_state = 0;
                        if (self.state != next_state) {
                            self.state = next_state;
                            try self.ee.emit(.{ .which = which, .state = next_state });
                        }
                    }
                } else {
                    self.last_state = next_state;
                    self.time_in_state = 0;
                }
            }
        };

        switches: [count]Switch = undefined,

        pub fn init(pins: [count]Pin) Self {
            var self: Self = .{};
            for (pins, 0..) |pin, i| {
                self.switches[i] = .{ .pin = pin };
            }
            return self;
        }

        pub fn schedule(self: *Self, slot: *sched.ScheduleSlot) void {
            const deadline = slot.now.add_duration(time.Duration.from_us(POLL_DELAY));
            slot.schedule(deadline, task, self);
        }

        pub fn get(self: *Self, index: SwitchMap) *Switch {
            return &self.switches[@backingInt(index)];
        }

        fn task(ctx: *anyopaque, slot: *sched.ScheduleSlot) !void {
            const self: *Self = @ptrCast(@alignCast(ctx));

            for (&self.switches, 0..) |*sw, index| {
                try sw.poll(@fromBackingInt(@intCast(index)));
            }

            self.schedule(slot);
        }
    };
}
