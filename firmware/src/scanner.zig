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

const Blinker = @import("drivers/Blinker.zig");
const switchset = @import("drivers/switchset.zig");
const TMC2209 = @import("drivers/TMC2209.zig");

const SerialEngine = @import("scanner/SerialEngine.zig");
const App = @import("scanner/App.zig");

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
fn onOpto(ctx: *anyopaque, payload: Switches.SwitchEvent) !void {
    _ = ctx;
    std.log.info("opto {any}", .{payload.state});
}
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

const SwitchMap = enum(u8) { RED, YEL, BLU, BLK, OPTO };
const Switches = switchset.SwitcheSet(SwitchMap, 3);

pub fn main() !void {
    logging.init(.{});
    std.log.info("Starting...", .{});
    const pins = pin_config.apply();

    pins.pdn_tx.set_function(.uart);
    pins.pdn_rx.set_function(.uart);

    const uart = hal.uart.instance.num(1);
    var app: App = .init(.{
        .uart = uart,
        .stepper_config = .{
            .step_pin = pins.step,
            .dir_pin = pins.dir,
        },
        .opto_pin = pins.lim_opto,
    });

    uart.apply(.{ .clock_config = hal.clock_config });

    pins.en.put(0);
    pins.mode1.put(0);
    pins.mode2.put(0);

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
        pins.lim_opto,
    });

    switches.addListener(.RED, SwitchBox.onSwitch, &box);
    switches.addListener(.YEL, SwitchBox.onSwitch, &box);
    switches.addListener(.BLU, SwitchBox.onSwitch, &box);
    switches.addListener(.BLK, SwitchBox.onSwitch, &box);
    switches.addListener(.OPTO, onOpto, &.{});
    switches.schedule(app.slow_scheduler.pri(0));

    var blinker: Blinker = .init(pins.led, 100_000);
    blinker.schedule(app.slow_scheduler.pri(1));

    try app.start();
}
