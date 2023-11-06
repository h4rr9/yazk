const std = @import("std");
const builtin = std.builtin;

const multiboot = @import("multiboot.zig");
const Kernel = @import("Kernel.zig");
const debug = @import("debug.zig");
const Console = @import("Console.zig");

const run_logger = std.log.scoped(.run);

pub const std_options = struct {
    pub const logFn = Kernel.logFn;
};

// embedding in file works for non-Debug builds.
comptime {
    asm (@embedFile("boot.s"));
}

export fn kmain(multiboot_magic: u32, info: *const multiboot.MultibootInfo) void {
    var kernel = Kernel.init(multiboot_magic, info) catch |e| {
        std.log.err("kernel Initialization failed with {!}", .{e});
        @panic("kernel Initialization failed");
    };
    kernel.run() catch |e| {
        std.log.err("kernel run failed with {!}", .{e});
        @panic("kernel run failed");
    };
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, return_addr: ?u32) noreturn {
    @setCold(true);
    debug.panic(error_return_trace, return_addr, "{s}", .{msg});
}
