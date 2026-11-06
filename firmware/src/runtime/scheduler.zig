// Simple scheduler
const std = @import("std");

const microzig = @import("microzig");

const callback = @import("callback.zig");

const time = microzig.drivers.time;

const assert = std.debug.assert;

pub const TaskHandler = fn (ctx: *anyopaque, slot: *ScheduleSlot) anyerror!void;
pub const Now = time.Absolute.from_us(0);
pub const Never = time.Absolute.from_us(std.math.maxInt(u64));

pub const SchedulerState = enum { IDLE, RUNNING };
pub const SchedulerHook = callback.makeCallback(SchedulerState);

/// A single scheduler slot
pub const ScheduleSlot = struct {
    const Self = @This();

    now: time.Absolute = Now,
    then: time.Absolute = Never,
    deadline: time.Absolute = Never,
    handler: *const TaskHandler = undefined,
    context: *anyopaque = undefined,

    pub fn schedule(
        self: *Self,
        deadline: time.Absolute,
        handler: TaskHandler,
        context: *anyopaque,
    ) void {
        assert(self.deadline == Never);
        self.handler = handler;
        self.context = context;
        self.deadline = deadline;
    }

    pub fn delay(self: *Self, delay_us: u64) void {
        assert(self.deadline == Never);
        self.deadline = self.now.add_duration(time.Duration.from_us(delay_us));
    }

    pub fn pollWithHook(self: *Self, now: time.Absolute, hook: ?SchedulerHook) !bool {
        if (self.deadline.is_reached_by(now)) {
            self.then = self.now; // remember when we were scheduled
            self.now = now;
            self.deadline = Never;
            if (hook) |h| {
                h.advise(.RUNNING);
                defer h.advise(.IDLE);
                try self.handler(self.context, self);
            } else {
                try self.handler(self.context, self);
            }
            return true;
        }

        return false;
    }

    pub fn lastScheduled(self: *Self) time.Absolute {
        // If we have never been scheduled fall back to now
        if (self.then == Never)
            return self.now;
        return self.then;
    }

    pub fn poll(self: *Self, now: time.Absolute) !bool {
        return try self.pollWithHook(now, null);
    }
};

pub fn makeScheduler(comptime size: u8) type {
    return struct {
        const Self = @This();
        pub const empty: Self = .{};

        slots: [size]ScheduleSlot = @splat(.{}),

        fn adjustPriority(self: *Self, pos: usize) void {
            for (pos + 1..size, pos..) |hi, lo| {
                if (self.slots[hi].deadline.is_reached_by(self.slots[lo].deadline)) {
                    const t = self.slots[lo];
                    self.slots[lo] = self.slots[hi];
                    self.slots[hi] = t;
                }
            }
        }

        pub fn pollWithHook(self: *Self, now: time.Absolute, hook: ?SchedulerHook) !bool {
            for (&self.slots, 0..) |*slot, pos| {
                if (try slot.pollWithHook(now, hook)) {
                    self.adjustPriority(pos);
                    return true;
                }
            }
            return false;
        }

        pub fn poll(self: *Self, now: time.Absolute) !bool {
            return try self.pollWithHook(now, null);
        }

        pub fn pri(self: *Self, index: i9) *ScheduleSlot {
            const pos: u8 = if (index < 0) @intCast(size + index) else @intCast(index);
            assert(pos < size);
            const slot = &self.slots[pos];
            assert(slot.deadline == Never);
            return slot;
        }
    };
}

pub fn makeNestedScheduler(comptime size: u8, comptime every_us: u64) type {
    return struct {
        const Self = @This();
        scheduler: makeScheduler(size) = .empty,
        pub const empty: Self = .{};

        pub fn pri(self: *Self, index: i9) *ScheduleSlot {
            return self.scheduler.pri(index);
        }

        pub fn schedule(self: *Self, slot: *ScheduleSlot) void {
            const deadline = slot.now.add_duration(time.Duration.from_us(every_us));
            slot.schedule(deadline, task, self);
        }

        fn task(ctx: *anyopaque, slot: *ScheduleSlot) !void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            _ = try self.scheduler.poll(slot.now);
            self.schedule(slot);
        }
    };
}
