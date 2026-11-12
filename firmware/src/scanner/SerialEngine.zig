const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;

const assert = std.debug.assert;

const events = @import("../runtime/events.zig");
const sched = @import("../runtime/scheduler.zig");

const TMC2209 = @import("../drivers/TMC2209.zig");

const Datagram = TMC2209.Datagram;

const Self = @This();

const SerialCommand = struct {
    pub const Emitter = events.Emitter(TMC2209.SerialIO.Event, 2);
    request: Datagram,
    ee: Emitter = .empty,
};

pub const QUEUE_SIZE = 16;
const PERIOD = 100;

sio: TMC2209.SerialIO,
queue: [QUEUE_SIZE]SerialCommand = undefined,
q_start: u8 = 0,
q_len: u8 = 0,
running: bool = false,
ee: events.Emitter(void, 3) = .empty,

pub fn init(uart: hal.uart.UART) Self {
    return .{ .sio = .init(uart) };
}

pub fn schedule(self: *Self, slot: *sched.ScheduleSlot) void {
    self.sio.ee.addListener(listener, self);
    slot.schedule(slot.now, task, self);
}

pub fn enqueue(self: *Self, dg: Datagram) ?*SerialCommand.Emitter {
    assert(self.q_len <= QUEUE_SIZE);
    if (self.q_len == QUEUE_SIZE)
        return null;
    defer self.q_len += 1;
    const q_end = (self.q_start + self.q_len) % QUEUE_SIZE;
    const slot: *SerialCommand = &self.queue[q_end];
    slot.request = dg;
    slot.ee.reset();
    if (!self.running)
        self.start();
    return &slot.ee;
}

fn retire(self: *Self) void {
    assert(self.running);
    self.q_start = (self.q_start + 1) % QUEUE_SIZE;
    self.q_len -= 1;
    self.running = false;
}

fn currentCommand(self: *Self) ?*SerialCommand {
    if (self.q_len == 0)
        return null;
    return &self.queue[self.q_start];
}

fn start(self: *Self) void {
    assert(!self.running);
    if (self.currentCommand()) |cmd| {
        self.running = true;
        self.sio.send(cmd.request);
    }
}

fn task(ctx: *anyopaque, slot: *sched.ScheduleSlot) !void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    self.sio.poll();
    slot.delay(PERIOD);
}

fn listener(ctx: *anyopaque, payload: TMC2209.SerialIO.Event) !void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    const cmd = self.currentCommand().?;
    // std.log.debug("listener received {any}", .{payload});
    try cmd.ee.emit(payload);

    self.retire();
    self.start();
    if (!self.running)
        try self.ee.emit();
}
