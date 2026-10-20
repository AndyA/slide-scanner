const std = @import("std");
const microzig = @import("microzig");

const MicroBuild = microzig.MicroBuild(.{
    .rp2xxx = true,
});

const firmwares: []const []const u8 = &.{
    "scanner", // default
    "playground",
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const opt_program = b.option(
        bool,
        "program",
        "Program an attached RP2040 with the selected firmware",
    ) orelse false;

    const rp_default_config = "etc/rp2040.cfg";
    const rp_config = b.option(
        []const u8,
        "config",
        "OpenOCD config (default \"" ++ rp_default_config ++ "\")",
    ) orelse rp_default_config;

    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return;
    const build_all = b.step("all", "Build all firmwares");

    inline for (firmwares, 0..) |app_name, index| {
        const firmware = mb.add_firmware(.{
            .name = app_name,
            .target = mb.ports.rp2xxx.boards.raspberrypi.pico,
            .optimize = .ReleaseSafe,
            .root_source_file = b.path("src/" ++ app_name ++ ".zig"),
        });

        mb.install_firmware(firmware, .{});
        const elf = mb.add_install_firmware(firmware, .{ .format = .elf });

        const build_step = b.step(app_name, "Build the " ++ app_name ++ " firmware");
        if (opt_program) {
            const openocd = b.addSystemCommand(&.{"openocd"});
            openocd.addArgs(&.{
                "-f", "etc/cmis-dap.cfg", //
                "-f", rp_config, //
                "-c", "adapter speed 5000", //
                "-c", "program zig-out/firmware/" ++ app_name ++ ".elf verify reset exit", //
            });
            openocd.step.dependOn(&elf.step);
            build_step.dependOn(&openocd.step);
        } else {
            build_step.dependOn((&elf.step));
        }

        build_all.dependOn(build_step);

        // First firmware is the default
        if (index == 0)
            mb.builder.getInstallStep().dependOn(build_step);
    }

    // Mule
    const mule = b.addExecutable(.{
        .name = "mule",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mule.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const mule_install = b.addInstallArtifact(mule, .{});

    const mule_step = b.step("mule", "Run the mule");
    const mule_cmd = b.addRunArtifact(mule);
    mule_step.dependOn(&mule_cmd.step);
    mule_cmd.step.dependOn(&mule_install.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mule.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const unit_tests_run = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run platform agnostic unit tests");
    test_step.dependOn(&unit_tests_run.step);
}
