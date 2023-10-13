const std = @import("std");

const console = @import("console.zig");

const ALIGN = 1 << 0; // 0000 0001 - one left shift zero
const MEMINFO = 1 << 1; // 0000 0010 - one left shift 1
const MAGIC = 0x1BADB002; // GRUB magic
const FLAGS = ALIGN | MEMINFO;
const MultibootHeader = extern struct {
    magic: i32 = MAGIC,
    flags: i32,
    checksum: i32,
};
const MultibootInfo = extern struct {
    // Multiboot info version number
    flags: u32,

    // Available memory from BIOS
    mem_lower: u32,
    mem_upper: u32,

    // "root" partition
    boot_device: u32,

    // Kernel command line
    cmdline: u32,

    // Boot-Module list
    mods_count: u32,
    mods_addr: u32,

    dummy: [16]u8,

    // Memory Mapping buffer
    mmap_length: u32,
    mmap_addr: u32,

    // Drive Info buffer
    drives_length: u32,
    drives_addr: u32,

    // ROM configuration table
    config_table: u32,

    // Boot Loader Name
    boot_loader_name: [*:0]const u8,

    // APM table
    apm_table: u32,

    vbe_control_info: u32,
    vbe_mode_info: u32,
    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,

    framebuffer_addr: u64,
    framebuffer_pitch: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
    framebuffer_bpp: u8,
    framebuffer_type: u8,
    color_info: [6]u8,
};

const MultibootMmapEntry = packed struct {
    size: u32,
    addr_low: u32,
    addr_high: u32,
    len_low: u32,
    len_high: u32,
    type: u32,
};

export var _ align(4) linksection(".multiboot") = MultibootHeader{
    .flags = FLAGS,
    .checksum = -(MAGIC + FLAGS),
};

export fn _start() align(4) linksection(".text") callconv(.C) noreturn {
    asm volatile ("mov $0x1000000, %esp");
    var multiboot_magic: u32 = asm volatile ("mov %eax, %[ret]"
        : [ret] "={eax}" (-> u32),
        :
        : "eax"
    );
    var info: *const MultibootInfo = asm volatile ("mov %ebx, %[ret]"
        : [ret] "={ebx}" (-> *const MultibootInfo),
        :
        : "ebx"
    );
    @call(.auto, kernelMain, .{ multiboot_magic, info });
    while (true) std.atomic.spinLoopHint();
}

export fn panic() void {}

fn kernelMain(multiboot_magic: u32, info: *const MultibootInfo) void {
    console.initialize();

    console.printf("valid mmap ::: {d}\n", .{info.flags >> 6 & 0x1});
    console.printf("magic ::: {x}\n", .{multiboot_magic});
    console.printf("flags ::: {x}\n", .{info.flags});
    console.printf("bootloader name ::: {s}\n", .{info.boot_loader_name});
    console.printf("mmap length ::: {d}\n", .{info.mmap_length});

    const mmap = @as([*]MultibootMmapEntry, @ptrFromInt(info.mmap_addr));
    const len = info.mmap_length / @sizeOf(MultibootMmapEntry);
    console.printf("num mmap = {d}\n", .{len});

    var total_len: u32 = 0;
    for (0..len) |i| {
        const size_kb: f32 = @as(f32, @floatFromInt(mmap[i].len_low)) / 1024.0;
        total_len += mmap[i].len_low;
        console.printf("size: {d}, len: {d}K, start addr: {x}, type ::: {d}\n", .{ mmap[i].size, size_kb, mmap[i].addr_low, mmap[i].type });
    }
    console.printf("total mmap len ::: {d:.2}M", .{@as(f32, @floatFromInt(total_len)) / 1024.0 / 1024.0});
}
