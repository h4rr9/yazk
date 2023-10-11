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

    const kernel_step = b.step("kernel", "Build the kernel");
    kernel_step.dependOn(&kernel_install.step);

    const iso_dir = b.fmt("{s}/iso_root", .{b.cache_root.path.?});
    const iso_dir_boot = b.fmt("{s}/iso_root/boot", .{b.cache_root.path.?});
    const iso_dir_boot_grub = b.fmt("{s}/iso_root/boot/grub", .{b.cache_root.path.?});
    const kernel_path = b.getInstallPath(kernel_install.dest_dir.?, kernel.out_filename);
    const iso_path = b.fmt("{s}/disk.iso", .{b.exe_dir});

    const iso_cmd_str = &[_][]const u8{
        "/bin/sh", "-c", std.mem.concat(b.allocator, u8, &[_][]const u8{
            "mkdir -p ",       iso_dir_boot_grub, " && ",
            "cp ",             kernel_path,       " ",
            iso_dir_boot,      " && ",            "cp src/grub.cfg ",
            iso_dir_boot_grub, " && ",            "grub-mkrescue -o ",
            iso_path,          " ",               iso_dir,
        }) catch unreachable,
    };

    const iso_cmd = b.addSystemCommand(iso_cmd_str);
    iso_cmd.step.dependOn(kernel_step);

    const iso_step = b.step("iso", "Build an ISO image");
    iso_step.dependOn(&iso_cmd.step);

    b.default_step.dependOn(iso_step);

    const run_iso_cmd_str = &[_][]const u8{
        "qemu-system-x86_64",
        "-cdrom",
        iso_path,
        "-debugcon",
        "stdio",
        "-vga",
        "virtio",
        "-m",
        "4G",
        "-no-reboot",
        "-no-shutdown",
    };
    const run_iso_cmd = b.addSystemCommand(run_iso_cmd_str);
    run_iso_cmd.step.dependOn(b.getInstallStep());

    const run_iso_step = b.step("run", "Run the iso");
    run_iso_step.dependOn(&run_iso_cmd.step);

    const run_kernel_cmd_str = &[_][]const u8{
        "qemu-system-x86_64",
        "-kernel",
        kernel_path,
    };
    const run_kernel_cmd = b.addSystemCommand(run_kernel_cmd_str);
    run_kernel_cmd.step.dependOn(b.getInstallStep());

    const run_kernel_step = b.step("run-kernel", "Run the kernel");
    run_kernel_step.dependOn(&run_kernel_cmd.step);
}
