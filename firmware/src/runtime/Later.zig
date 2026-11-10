const std = @import("std");
const assert = std.debug.assert;

const Self = @This();
pub const Worker = *const fn (ctx: *anyopaque) void;

pub const empty: Self = .{};

var head: ?*Self = null;
var tail: ?*Self = null;

next: ?*Self = null,
worker: ?Worker = null,
ctx: *anyopaque = undefined,

pub fn schedule(self: *Self, worker: Worker, ctx: *anyopaque) void {
    assert(self.next == null);
    assert(self.worker == null);
    self.worker = worker;
    self.ctx = ctx;
    if (tail) |t| t.next = self else head = self;
    tail = self;
}

pub fn ensure(self: *Self, worker: Worker, ctx: *anyopaque) void {
    if (self.worker == null) {
        self.schedule(worker, ctx);
    } else {
        assert(self.worker == worker);
        assert(self.ctx == ctx);
    }
}

pub fn cancel(self: *Self) void {
    if (self.worker == null)
        return;
    self.worker = null;
    var tick = head;
    var prev: ?*Self = null;
    while (tick) |t| {
        if (t == self) {
            if (prev) |p| p.next = self.next else head = self.next;
            if (tail == self) tail = prev;
            return;
        }
        prev = t;
        tick = t.next;
    }
}

pub fn run() void {
    var tick = head;
    while (tick) |t| {
        tick = t.next;
        t.next = null;
        t.worker.?(t.ctx);
        t.worker = null;
    }
    head = null;
    tail = null;
}
