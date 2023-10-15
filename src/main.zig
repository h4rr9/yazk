const std = @import("std");
const builtin = std.builtin;

const console = @import("console.zig");
const multiboot = @import("multiboot.zig");
const ally = @import("ally.zig");
const layout = @import("layout.zig");
const debug = @import("debug.zig");

const MultibootMmapEntry = multiboot.MultibootMmapEntry;

extern fn getESP() u32;

/// The size of the fixed allocator used before the heap is set up. Set to 1MiB.
pub var fixed_buffer: [1024 * 1024]u8 = undefined;

/// The fixed allocator used before the heap is set up.
pub var fixed_buffer_allocator: std.heap.FixedBufferAllocator = std.heap.FixedBufferAllocator.init(fixed_buffer[0..]);

export fn kmain(multiboot_magic: u32, info: *const multiboot.MultibootInfo) void {
    console.initialize();

    console.write("magic ::: {x}", .{multiboot_magic});
    console.write("valid mmap ::: {d}", .{info.flags >> 6 & 0x1});
    console.write("flags ::: {x}", .{info.flags});
    console.write("bootloader name ::: {s}", .{info.boot_loader_name});
    console.write("mmap length ::: {d}", .{info.mmap_length});

    console.write("num mmap = {d}", .{info.getNumMmap()});

    var total_len: u32 = 0;
    for (info.getMmapAddrs()) |mmap| if (mmap.type == multiboot.MULTIBOOT_MEMORY_AVAILABLE) {
        const size_kb: f32 = @as(f32, @floatFromInt(mmap.len)) / 1024.0;
        total_len += mmap.len;
        console.write("size: {d}, len: {d}K, start addr: {x}", .{ mmap.size, size_kb, mmap.addr });
    };
    console.write("total mmap len ::: {d:.2}M", .{@as(f32, @floatFromInt(total_len)) / 1024.0 / 1024.0});
    const kernel_start: usize = @intFromPtr(&layout.KERNEL_START);
    const kernel_end: usize = @intFromPtr(&layout.KERNEL_END);
    console.write("KERNEL_START = {x}, KERNEL_END = {x}", .{ kernel_start, kernel_end });
    console.write("STACK POINTER = {x}", .{getESP()});

    console.write("Module len: {d}", .{info.mods_count});

    debug.initSymbols(info.getModules(), fixed_buffer_allocator.allocator()) catch @panic("Failed to initialize debug symbols.");

    var alloc = ally.Allocator.init(info);
    _ = std.ArrayList(u8).initCapacity(alloc.allocator(), 10) catch {};
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, return_addr: ?usize) noreturn {
    @setCold(true);
    debug.panic(error_return_trace, return_addr, "{s}", .{msg});
}
