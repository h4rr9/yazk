const std = @import("std");
const builtin = std.builtin;

const Console = @import("Console.zig");
const multiboot = @import("multiboot.zig");
const Ally = @import("Ally.zig");
const layout = @import("layout.zig");
const debug = @import("debug.zig");
const Serial = @import("Serial.zig");
const Screen = @import("Screen.zig");
const PortManager = @import("PortManager.zig");

const boot_logger = std.log.scoped(.boot);

// embedding in file works for non-Debug builds.
comptime {
    asm (@embedFile("boot.s"));
}

/// GLOBAL VARIABLES
/// The size of the fixed allocator used before the heap is set up. Set to 2MiB.
var fixed_buffer: [2 * 1024 * 1024]u8 = undefined;

/// The fixed allocator used before the heap is set up.
pub var fixed_buffer_allocator: std.heap.FixedBufferAllocator = std.heap.FixedBufferAllocator.init(fixed_buffer[0..]);
const fixed_buffer_ally = fixed_buffer_allocator.allocator();

/// global PortManager and Serial interface
var port_manager: PortManager = undefined;
var serial: Serial = undefined;
var serial_writer: Serial.SerialWriter = undefined;
var ally: Ally = undefined;
var kernel_allocator: std.mem.Allocator = undefined;

pub const std_options = struct {
    pub const logFn = struct {
        pub fn log(
            comptime message_level: std.log.Level,
            comptime scope: @Type(.EnumLiteral),
            comptime format: []const u8,
            args: anytype,
        ) void {
            const level_txt = comptime message_level.asText();
            const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
            serial_writer.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch unreachable;
        }
    }.log;
};

export fn kmain(multiboot_magic: u32, info: *const multiboot.MultibootInfo) void {
    _ = multiboot_magic;
    // initialize Global Variables
    port_manager = PortManager.init(fixed_buffer_ally);
    serial = Serial.initialize(&port_manager) catch |e| errorHelper(std.log, e, "Serial Initialization Failed");
    serial_writer = serial.writer();
    boot_logger.info("initialized serial interface.", .{});

    // must come after serial as it uses log
    boot_logger.info("initializing panic handler and debug symbols", .{});
    debug.initSymbols(info.getModules(), fixed_buffer_ally) catch @panic("Failed to initialize debug symbols.");

    boot_logger.info("initializing memory allocator.", .{});
    ally = Ally.init(info);
    kernel_allocator = ally.allocator();
    boot_logger.info("initialed memory allocator.", .{});

    {
        Console.initialize();
        boot_logger.info("console initialized", .{});
        Console.write("bootloader name ::: {s}", .{info.boot_loader_name});
    }

    var arr_a = std.ArrayList(u8).initCapacity(kernel_allocator, 2) catch @panic("allocating arr");
    defer arr_a.deinit();

    arr_a.append(1) catch @panic("appending 1");
    arr_a.append(2) catch @panic("appending 2");
    arr_a.append(3) catch @panic("appending 3");
    arr_a.append(4) catch @panic("appending 4");
    arr_a.append(5) catch @panic("appending 5");
    arr_a.append(6) catch @panic("appending 6");

    const testStruct = struct { u32, u32, u32, u128 };

    var ts = kernel_allocator.create(testStruct) catch @panic("out of memory");
    defer kernel_allocator.destroy(ts);

    ts.* = .{ 2, 2, 2, 2 };

    boot_logger.info("framebuffer_height: {d}", .{info.framebuffer_height});
    boot_logger.info("framebuffer_width: {d}", .{info.framebuffer_width});
    boot_logger.info("framebuffer_bpp: {d}", .{info.framebuffer_bpp});
    boot_logger.info("framebuffer_pitch: {d}", .{info.framebuffer_pitch});
    boot_logger.info("framebuffer_addr: 0x{x}", .{info.framebuffer_addr});
    boot_logger.info("screen initializing", .{});

    const screen = Screen.initialize(info) catch |e| errorHelper(boot_logger, e, "Screen initialization failed");

    boot_logger.info("screen initialized", .{});

    screen.drawCircle(screen.height / 16, screen.height / 2, screen.height / 4, .{ .rgb = .{ .r = 0, .g = 0, .b = 255 } });
    screen.drawCircle(0, 0, screen.height / 4, .{ .rgb = .{ .r = 255, .g = 255, .b = 255 } });
}

fn errorHelper(comptime logger: anytype, e: anyerror, comptime context: []const u8) noreturn {
    logger.err(context ++ " with {!}", .{e});
    @panic(context);
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, return_addr: ?u32) noreturn {
    @setCold(true);
    debug.panic(error_return_trace, return_addr, "{s}", .{msg});
}
