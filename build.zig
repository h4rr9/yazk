const std = @import("std");
const Target = @import("std").Target;
const Build = @import("std").Build;
const CrossTarget = @import("std").zig.CrossTarget;
const Feature = @import("std").Target.Cpu.Feature;
const InstallArtifact = @import("std").Build.Step.InstallArtifact;
const InstallDir = @import("std").Build.InstallDir;

pub fn build(b: *std.Build) void {
    const features = Target.x86.Feature;

    var enabled_features = Feature.Set.empty;
    var disabled_features = Feature.Set.empty;

    disabled_features.addFeature(@intFromEnum(features.mmx));
    disabled_features.addFeature(@intFromEnum(features.sse));
    disabled_features.addFeature(@intFromEnum(features.sse2));
    disabled_features.addFeature(@intFromEnum(features.avx));
    disabled_features.addFeature(@intFromEnum(features.avx2));
    enabled_features.addFeature(@intFromEnum(features.soft_float));

    const target = CrossTarget{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_sub = disabled_features,
        .cpu_features_add = enabled_features,
    };

    const optimize = b.standardOptimizeOption(.{});
    const kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    kernel.setLinkerScript(.{ .path = "src/linker.ld" });
    kernel.code_model = .kernel;
    var kernel_install = b.addInstallArtifact(kernel, .{});

    const iso_dir = b.fmt("{s}/iso_root", .{b.cache_root.path.?});
    const iso_dir_boot = b.fmt("{s}/iso_root/boot", .{b.cache_root.path.?});
    const iso_dir_modules = b.fmt("{s}/iso_root/modules", .{b.cache_root.path.?});
    const iso_dir_boot_grub = b.fmt("{s}/iso_root/boot/grub", .{b.cache_root.path.?});
    const kernel_path = b.getInstallPath(kernel_install.dest_dir.?, kernel.out_filename);
    const iso_path = b.fmt("{s}/disk.iso", .{b.exe_dir});
    const symbol_file_path = b.fmt("{s}/kernel.map", .{b.exe_dir});

    const symbol_info_cmd_str = &[_][]const u8{
        "/bin/sh", "-c", std.mem.concat(b.allocator, u8, &[_][]const u8{
            "mkdir -p ",
            iso_dir_modules,
            "&&",
            "readelf -s --wide ",
            kernel_path,
            "| grep -F \"FUNC\" | awk '{$1=$3=$4=$5=$6=$7=\"\"; print $0}' | sort -k 1 > ",
            symbol_file_path,
            " && ",
            "echo \"\" >> ",
            symbol_file_path,
        }) catch unreachable,
    };
    const symbol_cmd = b.addSystemCommand(symbol_info_cmd_str);
    symbol_cmd.step.dependOn(&kernel_install.step);

    const iso_cmd_str = &[_][]const u8{
        "/bin/sh", "-c", std.mem.concat(b.allocator, u8, &[_][]const u8{
            "mkdir -p ",
            iso_dir_boot_grub,
            " && ",
            "cp ",
            kernel_path,
            " ",
            iso_dir_boot,
            " && ",
            "cp src/grub.cfg ",
            iso_dir_boot_grub,
            " && ",
            "cp ",
            symbol_file_path,
            " ",
            iso_dir_modules,
            " && ",
            "grub-mkrescue -o ",
            iso_path,
            " ",
            iso_dir,
            " 2> ",
            "/dev/null",
        }) catch unreachable,
    };

    const iso_cmd = b.addSystemCommand(iso_cmd_str);
    iso_cmd.step.dependOn(&symbol_cmd.step);

    const qemu_iso_cmd_str = &[_][]const u8{
        "qemu-system-x86_64",
        "-cdrom",
        iso_path,
        "-serial",
        "stdio",
        "-debugcon",
        "file:debugcon.log",
        "-vga",
        "virtio",
        "-m",
        "4G",
        "-no-reboot",
        "-no-shutdown",
    };
    const qemu_iso_cmd = b.addSystemCommand(qemu_iso_cmd_str);
    qemu_iso_cmd.step.dependOn(b.getInstallStep());

    const qemu_kernel_cmd_str = &[_][]const u8{
        "qemu-system-x86_64",
        "-serial",
        "stdio",
        "-kernel",
        kernel_path,
    };

    const run_iso_step = b.step("run", "Run the iso");
    run_iso_step.dependOn(&qemu_iso_cmd.step);

    const qemu_kernel_cmd = b.addSystemCommand(qemu_kernel_cmd_str);
    qemu_kernel_cmd.step.dependOn(&kernel_install.step);

    const run_kernel_step = b.step("run-kernel", "Run the kernel");
    run_kernel_step.dependOn(&qemu_kernel_cmd.step);

    const kernel_step = b.step("kernel", "Build the kernel");
    kernel_step.dependOn(&kernel_install.step);

    const symbol_run_step = b.step("symbol", "Build kernel.map");
    symbol_run_step.dependOn(&symbol_cmd.step);

    const iso_step = b.step("iso", "Build an ISO image");
    iso_step.dependOn(&iso_cmd.step);

    // Creates a step for unit testing. This only builds the test executable but does not run it.
    const test_target = CrossTarget{
        .cpu_arch = .x86,
        .os_tag = .linux,
        .abi = .none,
        .cpu_features_sub = disabled_features,
        .cpu_features_add = enabled_features,
    };
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test.zig" },
        .target = test_target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    b.default_step.dependOn(iso_step);
}
