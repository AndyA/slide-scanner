const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;
const time = microzig.drivers.time;

const assert = std.debug.assert;

const logging = @import("runtime/logging.zig");
const sched = @import("runtime/scheduler.zig");
const Blinker = @import("drivers/Blinker.zig");
const switchset = @import("drivers/switchset.zig");

const TMC2209 = @import("drivers/TMC2209.zig");

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

// Compile-time pin configuration
const pin_config = hal.pins.GlobalConfiguration{
    .GPIO2 = .{ .name = "red_led", .direction = .out },
    .GPIO3 = .{ .name = "red_sw", .direction = .in, .pull = .up },
    .GPIO4 = .{ .name = "yel_led", .direction = .out },
    .GPIO5 = .{ .name = "yel_sw", .direction = .in, .pull = .up },
    .GPIO6 = .{ .name = "blu_led", .direction = .out },
    .GPIO7 = .{ .name = "blu_sw", .direction = .in, .pull = .up },
    .GPIO8 = .{ .name = "blk_led", .direction = .out },
    .GPIO9 = .{ .name = "blk_sw", .direction = .in, .pull = .up },
    .GPIO25 = .{ .name = "led", .direction = .out },

    // Stepper
    .GPIO15 = .{ .name = "diag", .direction = .in, .pull = .up },
    .GPIO16 = .{ .name = "dir", .direction = .out },
    .GPIO17 = .{ .name = "step", .direction = .out },
    .GPIO18 = .{ .name = "mode2", .direction = .out },
    .GPIO19 = .{ .name = "mode1", .direction = .out },
    .GPIO20 = .{ .name = "pdn_tx", .direction = .out },
    .GPIO21 = .{ .name = "pdn_rx", .direction = .in },
    .GPIO22 = .{ .name = "en", .direction = .out },
};

const SwitchMap = enum(u8) { RED, YEL, BLU, BLK };
const Switches = switchset.SwitcheSet(SwitchMap, 3);

const FastScheduler = sched.makeScheduler(8);
const SlowScheduler = sched.makeNestedScheduler(8, 250);

const SwitchBox = struct {
    const Self = @This();
    pins: [4]Pin,

    fn onSwitch(ctx: *anyopaque, payload: Switches.SwitchEvent) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        std.log.info("{s} {any}", .{ @tagName(payload.which), payload.state });
        if (payload.state) {
            self.pins[@backingInt(payload.which)].toggle();
        }
    }
};

const uart = hal.uart.instance.num(1);

const SerialTask = struct {
    const Self = @This();

    const PERIOD = 100;

    sio: TMC2209.SerialIO = undefined,
    sequence: []const TMC2209.Datagram = undefined,
    pos: u8 = 0,

    pub fn init(u: hal.uart.UART, sequence: []const TMC2209.Datagram) Self {
        return .{ .sio = .init(u), .sequence = sequence };
    }

    pub fn schedule(self: *Self, slot: *sched.ScheduleSlot) void {
        self.sio.ee.addListener(listener, self);
        slot.schedule(slot.now, task, self);
    }

    fn task(ctx: *anyopaque, slot: *sched.ScheduleSlot) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.sio.poll();
        slot.delay(PERIOD);
    }

    fn nextDatagram(self: *Self) ?TMC2209.Datagram {
        if (self.pos == self.sequence.len)
            return null;
        defer self.pos += 1;
        return self.sequence[self.pos];
    }

    pub fn pump(self: *Self) void {
        if (self.nextDatagram()) |dg| {
            std.log.info("sending {f}", .{dg});
            self.sio.send(dg);
        } else std.log.info("All Datagrams sent", .{});
    }

    fn listener(ctx: *anyopaque, payload: TMC2209.SerialIO.Event) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        switch (payload) {
            .data => |dg| {
                std.log.info("sio event: {s} {f}", .{ @tagName(payload), dg });
                self.pump();
            },
            .ready => {
                std.log.info("sio event: {s}", .{@tagName(payload)});
                self.pump();
            },
            else => {
                std.log.info("sio event: {s}", .{@tagName(payload)});
            },
        }
    }
};

pub fn main() !void {
    logging.init(.{});
    std.log.info("Starting...", .{});
    const pins = pin_config.apply();
    var root_scheduler: FastScheduler = .empty;
    var slow_scheduler: SlowScheduler = .empty;

    slow_scheduler.schedule(root_scheduler.pri(-1));

    pins.pdn_tx.set_function(.uart);
    pins.pdn_rx.set_function(.uart);

    uart.apply(.{ .clock_config = hal.clock_config });

    pins.en.put(0);
    pins.mode1.put(0);
    pins.mode2.put(0);

    const addr: u8 = 0;
    var ser: SerialTask = .init(uart, &.{
        TMC2209.Datagram.initRead(addr, .IFCNT),
        TMC2209.Datagram.initRead(addr, .DRV_STATUS),
        TMC2209.Datagram.initWrite(addr, .VACTUAL, 10_000),
        TMC2209.Datagram.initRead(addr, .VACTUAL),
        TMC2209.Datagram.initRead(addr, .IFCNT),
        TMC2209.Datagram.initRead(addr, .DRV_STATUS),
    });
    ser.schedule(root_scheduler.pri(0));

    var box: SwitchBox = .{ .pins = .{
        pins.red_led,
        pins.yel_led,
        pins.blu_led,
        pins.blk_led,
    } };

    var switches: Switches = .init(.{
        pins.red_sw,
        pins.yel_sw,
        pins.blu_sw,
        pins.blk_sw,
    });

    switches.addListener(.RED, SwitchBox.onSwitch, &box);
    switches.addListener(.YEL, SwitchBox.onSwitch, &box);
    switches.addListener(.BLU, SwitchBox.onSwitch, &box);
    switches.addListener(.BLK, SwitchBox.onSwitch, &box);
    switches.schedule(slow_scheduler.pri(0));

    var blinker: Blinker = .init(pins.led, 100_000);
    blinker.schedule(slow_scheduler.pri(1));

    ser.pump();

    while (true) {
        _ = try root_scheduler.poll(hal.time.get_time_since_boot());
    }
}
