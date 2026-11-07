const microzig = @import("microzig");

const hal = microzig.hal;
const time = hal.time;
const gpio = hal.gpio;

const led = gpio.num(25);
const uart = hal.uart.instance.num(0);
const uart_tx_pin = gpio.num(0);
const uart_rx_pin = gpio.num(1);

pub const panic = microzig.panic;

pub const std_options = microzig.std_options(.{});

comptime {
    _ = microzig.export_startup();
}

pub fn main() !void {
    led.set_function(.sio);
    led.set_direction(.out);
    led.put(1);
    inline for (&.{ uart_tx_pin, uart_rx_pin }) |pin| {
        pin.set_function(.uart);
    }

    uart.apply(.{
        .clock_config = hal.clock_config,
    });

    var data: [1]u8 = .{0};
    while (true) {
        const byte = uart.read_word() catch {
            uart.clear_errors();
            continue;
        };
        if (byte) |b| {
            data[0] = b;
            // Try to write one byte with 100ms timeout
            _ = uart.write_blocking(&data, time.deadline_in_ms(100)) catch {
                uart.clear_errors();
            };
            // Toggle the led every time we think we've received a character so we
            // know something is going on.
            led.toggle();
        }
    }
}
