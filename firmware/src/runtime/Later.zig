const std = @import("std");
const assert = std.debug.assert;

const Self = @This();
pub const Worker = *const fn (ctx: *anyopaque) void;

pub const empty: Self = .{};

var head: ?*Self = null;
var tail: ?*Self = null;

next: ?*Self = null,
worker: Worker = undefined,
ctx: *anyopaque = undefined,
scheduled: bool = false,

pub fn schedule(self: *Self, worker: Worker, ctx: *anyopaque) void {
    assert(!self.scheduled);
    self.worker = worker;
    self.ctx = ctx;
    self.scheduled = true;
    if (tail) |t| t.next = self else head = self;
    tail = self;
}

pub fn ensure(self: *Self, worker: Worker, ctx: *anyopaque) void {
    if (!self.scheduled) {
        self.schedule(worker, ctx);
    } else {
        assert(self.worker == worker);
        assert(self.ctx == ctx);
    }
}

pub fn cancel(self: *Self) void {
    if (self.worker == null)
        return;
    var tick = head;
    var prev: ?*Self = null;
    while (tick) |t| {
        if (t == self) {
            if (prev) |p| p.next = self.next else head = self.next;
            if (tail == self) tail = prev;
            self.scheduled = false;
            self.next = null;
            return;
        }
        prev = t;
        tick = t.next;
    }
}

pub fn poll() void {
    var tick = head;
    head, tail = .{ null, null };
    while (tick) |t| {
        tick = t.next;
        t.next = null;
        t.scheduled = false;
        t.worker(t.ctx);
    }
}

pub fn drain() void {
    while (head != null)
        poll();
}
