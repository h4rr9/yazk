const std = @import("std");
const builtin = std.builtin;

const console = @import("console.zig");
const multiboot = @import("multiboot.zig");
const ally = @import("ally.zig");
const layout = @import("layout.zig");
const debug = @import("debug.zig");
const log = @import("log.zig");

const boot_logger = std.log.scoped(.boot);

// embedding in file works for non-Debug builds.
comptime {
    asm (@embedFile("boot.s"));
}

pub const std_options = struct {
    pub const logFn = log.log;
};

const MultibootMmapEntry = multiboot.MultibootMmapEntry;

/// The size of the fixed allocator used before the heap is set up. Set to 1MiB.
pub var fixed_buffer: [1024 * 1024]u8 = undefined;

/// The fixed allocator used before the heap is set up.
pub var fixed_buffer_allocator: std.heap.FixedBufferAllocator = std.heap.FixedBufferAllocator.init(fixed_buffer[0..]);

export fn kmain(multiboot_magic: u32, info: *const multiboot.MultibootInfo) void {
    _ = multiboot_magic;

    console.initialize();
    boot_logger.info("console initialized", .{});

    console.write("bootloader name ::: {s}", .{info.boot_loader_name});

    boot_logger.info("initializing panic handler and debug symbols", .{});
    debug.initSymbols(info.getModules(), fixed_buffer_allocator.allocator()) catch @panic("Failed to initialize debug symbols.");

    boot_logger.info("initializing memory allocator", .{});
    var alloc = ally.init(info);
    var allocator = alloc.allocator();
    var arr_a = std.ArrayList(u8).initCapacity(allocator, 2) catch @panic("allocating arr");
    defer arr_a.deinit();

    arr_a.append(1) catch @panic("appending 1");
    arr_a.append(2) catch @panic("appending 2");
    arr_a.append(3) catch @panic("appending 3");
    arr_a.append(4) catch @panic("appending 4");
    arr_a.append(5) catch @panic("appending 5");
    arr_a.append(6) catch @panic("appending 6");

    const testStruct = struct { u32, u32, u32, u128 };

    var ts = allocator.create(testStruct) catch @panic("out of memory");
    defer allocator.destroy(ts);

    ts.* = .{ 2, 2, 2, 2 };
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, return_addr: ?u32) noreturn {
    @setCold(true);
    debug.panic(error_return_trace, return_addr, "{s}", .{msg});
}
