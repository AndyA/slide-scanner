const std = @import("std");
const microzig = @import("microzig");
const hal = microzig.hal;
const time = microzig.drivers.time;
const usb = microzig.core.usb;
const USB_Serial = usb.drivers.CDC;

const USB_Device = hal.usb.Polled(.{});

const assert = std.debug.assert;

const events = @import("runtime/events.zig");
const logging = @import("runtime/logging.zig");
const sched = @import("runtime/scheduler.zig");
const P = @import("runtime/promise.zig");
const Later = @import("runtime/Later.zig");

const Blinker = @import("drivers/Blinker.zig");
const switchset = @import("drivers/switchset.zig");
const TMC2209 = @import("drivers/TMC2209.zig");

const Datagram = TMC2209.Datagram;

const USBTask = @import("scanner/usb_task.zig").USBTask;

pub const std_options = microzig.std_options(.{
    .log_level = .debug,
    .log_scope_levels = &.{
        .{ .scope = .usb_dev, .level = .warn },
        .{ .scope = .usb_ctrl, .level = .warn },
        .{ .scope = .usb_cdc, .level = .warn },
    },
    .logFn = hal.uart.log,
});

comptime {
    _ = microzig.export_startup();
}

const USB_Controller = usb.DeviceController(.{
    .bcd_usb = USB_Device.max_supported_bcd_usb,
    .device_triple = .unspecified,
    .vendor = USB_Device.default_vendor_id,
    .product = USB_Device.default_product_id,
    .bcd_device = .v1_00,
    .serial = "scanner",
    .max_supported_packet_size = USB_Device.max_supported_packet_size,
    .configurations = &.{.{
        .attributes = .{ .self_powered = false },
        .max_current_ma = 50,
        .Drivers = struct {
            serial: USB_Serial,
            reset: hal.usb.ResetDriver(null, 0),
        },
    }},
}, .{.{
    .serial = .{ .itf_notifi = "Scanner CDC", .itf_data = "Scanner CDC Data" },
    .reset = "",
}});

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    std.log.err("panic: {s}", .{message});
    @breakpoint();
    while (true) {}
}

const Pin = hal.gpio.Pin;

// Compile-time pin configuration
const pin_config = hal.pins.GlobalConfiguration{
    .GPIO2 = .{ .name = "blk_sw", .direction = .in, .pull = .up },
    .GPIO3 = .{ .name = "blk_led", .direction = .out },
    .GPIO4 = .{ .name = "blu_sw", .direction = .in, .pull = .up },
    .GPIO5 = .{ .name = "blu_led", .direction = .out },
    .GPIO6 = .{ .name = "yel_sw", .direction = .in, .pull = .up },
    .GPIO7 = .{ .name = "yel_led", .direction = .out },
    .GPIO8 = .{ .name = "red_sw", .direction = .in, .pull = .up },
    .GPIO9 = .{ .name = "red_led", .direction = .out },
    .GPIO25 = .{ .name = "led", .direction = .out },

    // Stepper
    .GPIO15 = .{ .name = "lim_opto", .direction = .in, .pull = .up },
    .GPIO16 = .{ .name = "dir", .direction = .out },
    .GPIO17 = .{ .name = "step", .direction = .out },
    .GPIO18 = .{ .name = "mode2", .direction = .out },
    .GPIO19 = .{ .name = "mode1", .direction = .out },
    .GPIO20 = .{ .name = "pdn_tx", .direction = .out },
    .GPIO21 = .{ .name = "pdn_rx", .direction = .in },
    .GPIO22 = .{ .name = "en", .direction = .out },
};

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

const SerialCommand = struct {
    pub const Promise = P.Promise(?TMC2209.RegValue, 3);
    request: Datagram,
    promise: Promise = .empty,
};

const SerialEngine = struct {
    const Self = @This();

    pub const QUEUE_SIZE = 8;
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

    pub fn enqueue(self: *Self, dg: Datagram) ?*SerialCommand.Promise {
        assert(self.q_len <= QUEUE_SIZE);
        if (self.q_len == QUEUE_SIZE)
            return null;
        defer self.q_len += 1;
        const q_end = (self.q_start + self.q_len) % QUEUE_SIZE;
        const slot: *SerialCommand = &self.queue[q_end];
        slot.request = dg;
        slot.promise.reset();
        if (!self.running)
            self.start();
        return &slot.promise;
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
        std.log.debug("listener received {any}", .{payload});
        switch (payload) {
            .data => |dg| cmd.promise.resolve(dg.value()),
            .ready => cmd.promise.resolve(null),
            .data_err => cmd.promise.reject(error.SerialDataError),
            .crc_err => cmd.promise.reject(error.SerialCRCError),
            .timeout => cmd.promise.reject(error.SerialTimeout),
        }
        self.retire();
        self.start();
        if (!self.running)
            try self.ee.emit();
    }
};

pub const AppConfig = struct {
    stepper_addr: u2 = 0,
    uart: hal.uart.UART,
};

const FastScheduler = sched.makeScheduler(8);
const SlowScheduler = sched.makeNestedScheduler(8, 250);

pub const App = struct {
    const Self = @This();

    const State = enum { INIT };

    config: AppConfig,
    state: State = .INIT,
    root_scheduler: FastScheduler = .empty,
    slow_scheduler: SlowScheduler = .empty,
    ser: SerialEngine,

    pub fn init(config: AppConfig) Self {
        return .{
            .config = config,
            .ser = .init(config.uart),
        };
    }

    fn sendSetupCommands(self: *Self) void {
        const addr = self.config.stepper_addr;
        const cmds: []const Datagram = &.{
            Datagram.initWrite(addr, .{ .GCONF = .{
                .i_scale_analog = true,
                .pdn_disable = true,
                .mstep_reg_select = true,
                .shaft = true,
            } }),
            Datagram.initWrite(addr, .{ .CHOPCONF = .{
                .toff = 3,
                .h_strt = 5,
                .h_end = 0,
                .tbl = 2,
                .vsense_high = false,
                .mres = 4,
                .intpol = true,
                .dedge = false,
                .diss2g = false,
                .diss2vs = false,
            } }),
            Datagram.initWrite(addr, .{ .NODECONF = .{ .send_delay = 0 } }),
            Datagram.initWrite(addr, .{ .VACTUAL = .{ .speed = 0 } }),
        };
        for (cmds) |cmd| {
            _ = self.ser.enqueue(cmd);
        }
    }

    fn serialEvent(ctx: *anyopaque) !void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = self;
        std.log.debug("serial engine idle", .{});
    }

    fn installHandlers(self: *Self) void {
        self.ser.ee.addListener(serialEvent, self);
    }

    fn scheduleTasks(self: *Self) void {
        self.ser.schedule(self.root_scheduler.pri(1));
    }

    pub fn start(self: *Self) !void {
        self.slow_scheduler.schedule(self.root_scheduler.pri(-1));
        self.installHandlers();
        self.sendSetupCommands();
        self.scheduleTasks();

        while (true) {
            Later.poll();
            _ = try self.root_scheduler.poll(hal.time.get_time_since_boot());
        }
    }
};

const USB = USBTask(USB_Controller);

fn usbEvent(ctx: *anyopaque, event: USB.Event) !void {
    var buf: [1024]u8 = undefined;
    const task: *USB = @ptrCast(@alignCast(ctx));
    switch (event) {
        inline else => |data| {
            std.log.debug(
                "USB: {s} \"{s}\"",
                .{ @tagName(event), data },
            );
            const tx = std.fmt.bufPrint(&buf, "ack {s}\n", .{data}) catch &.{};
            _ = task.write(tx);
        },
    }
}

const SwitchMap = enum(u8) { RED, YEL, BLU, BLK };
const Switches = switchset.SwitcheSet(SwitchMap, 3);

pub fn main() !void {
    logging.init(.{});
    std.log.info("Starting...", .{});
    const pins = pin_config.apply();
    // var root_scheduler: FastScheduler = .empty;
    // var slow_scheduler: SlowScheduler = .empty;

    // slow_scheduler.schedule(root_scheduler.pri(-1));

    pins.pdn_tx.set_function(.uart);
    pins.pdn_rx.set_function(.uart);

    const uart = hal.uart.instance.num(1);
    var app: App = .init(.{ .uart = uart });

    uart.apply(.{ .clock_config = hal.clock_config });

    pins.en.put(0);
    pins.mode1.put(0);
    pins.mode2.put(0);

    var stepper: TMC2209.Stepper = .init(.{
        .step_pin = pins.step,
        .dir_pin = pins.dir,
    });
    try stepper.start(app.root_scheduler.pri(0));
    stepper.setSpeed(200 * 16);
    stepper.setRemaining(20_000 * 16);

    // app.ser.schedule(app.root_scheduler.pri(1));

    var usb_controller: USB_Controller = .init;
    var usb_device: USB_Device = .init();
    var usb_task: USB = .init(&usb_controller, &usb_device);
    usb_task.ee.addListener(usbEvent, &usb_task);
    usb_task.schedule(app.root_scheduler.pri(2));

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
    switches.schedule(app.slow_scheduler.pri(0));

    var blinker: Blinker = .init(pins.led, 100_000);
    blinker.schedule(app.slow_scheduler.pri(1));

    try app.start();
}
