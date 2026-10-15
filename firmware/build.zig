const std = @import("std");
const microzig = @import("microzig");

const MicroBuild = microzig.MicroBuild(.{
    .rp2xxx = true,
});

pub fn build(b: *std.Build) void {
    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return;

    const firmware = mb.add_firmware(.{
        .name = "scanner",
        .target = mb.ports.rp2xxx.boards.raspberrypi.pico,
        .optimize = .ReleaseSafe,
        .root_source_file = b.path("src/main.zig"),
    });

    mb.install_firmware(firmware, .{});
    const elf = mb.add_install_firmware(firmware, .{ .format = .elf });
    mb.builder.getInstallStep().dependOn(&elf.step);

    const rp_default_config = "etc/rp2040.cfg";
    const rp_config = b.option(
        []const u8,
        "config",
        b.fmt("rp2040 openocd config (default \"{s}\")", .{rp_default_config}),
    );

    const openocd = b.addSystemCommand(&.{"openocd"});
    openocd.addArgs(&.{
        "-f", "etc/cmis-dap.cfg", //
        "-f", rp_config orelse rp_default_config, //
        "-c", "adapter speed 5000", //
        "-c", "program zig-out/firmware/scanner.elf verify reset exit", //
    });
    openocd.step.dependOn(&elf.step);

    const prog_step = b.step("program", "Send to the RP2040");
    prog_step.dependOn(&openocd.step);
}
