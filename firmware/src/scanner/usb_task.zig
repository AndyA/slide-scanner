const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;
const usb = microzig.core.usb;
const USB_Serial = usb.drivers.CDC;

const USB_Device = hal.usb.Polled(.{});

const sched = @import("../runtime/scheduler.zig");
const events = @import("../runtime/events.zig");

const assert = std.debug.assert;

pub fn USBTask(comptime USB_Controller: type) type {
    const BUF_SIZE = 1024;
    return struct {
        const Self = @This();

        const PERIOD = 100;

        const State = enum(u8) { INIT, ACTIVE };

        pub const Event = union(enum) {
            line: []const u8,
            bulk: []const u8,
        };

        controller: *USB_Controller,
        device: *USB_Device = undefined,

        serial: *USB_Serial = undefined,

        ee: events.Emitter(Event, 5) = .empty,
        state: State = .INIT,
        rx_buf: [BUF_SIZE]u8 = undefined,
        tx_buf: [BUF_SIZE]u8 = undefined,
        rx_pos: u16 = 0,
        tx_pos: u16 = 0,

        pub fn init(controller: *USB_Controller, device: *USB_Device) Self {
            return .{ .controller = controller, .device = device };
        }

        pub fn schedule(self: *Self, slot: *sched.ScheduleSlot) void {
            slot.schedule(slot.now, task, self);
        }

        fn task(ctx: *anyopaque, slot: *sched.ScheduleSlot) !void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.device.poll(self.controller);
            try self.stateMachine();
            slot.delay(PERIOD);
        }

        fn goState(self: *Self, state: State) void {
            self.state = state;
            std.log.debug("USB state {s}", .{@tagName(state)});
        }

        fn advanceRead(self: *Self) !void {
            const len = self.serial.read(self.rx_buf[self.rx_pos..]);
            if (len != 0) {
                var cmd_start: u16 = 0;
                var start = self.rx_pos;
                const end: u16 = @intCast(start + len);
                while (std.mem.findScalar(u8, self.rx_buf[start..end], '\n')) |pos| {
                    try self.ee.emit(.{ .line = self.rx_buf[cmd_start..pos] });
                    start += @as(u16, @intCast(pos)) + 1;
                    cmd_start = start;
                }
                const remaining = end - start;
                @memcpy(
                    self.rx_buf[self.rx_pos..][0..remaining],
                    self.rx_buf[start..end],
                );
                self.rx_pos += remaining;
                if (self.rx_pos == BUF_SIZE) {
                    try self.ee.emit(.{ .bulk = &self.rx_buf });
                    self.rx_pos = 0;
                }
            }
        }

        fn stateMachine(self: *Self) !void {
            switch (self.state) {
                .INIT => {
                    if (self.controller.drivers()) |drivers| {
                        self.serial = &drivers.serial;
                        self.goState(.ACTIVE);
                    }
                },
                .ACTIVE => {
                    try self.advanceRead();
                },
            }
        }
    };
}
