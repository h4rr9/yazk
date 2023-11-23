const std = @import("std");
const PortManager = @import("PortManager.zig");
const Serial = @import("Serial.zig");
const Ally = @import("Ally.zig");
const multiboot = @import("multiboot.zig");
const debug = @import("debug.zig");
const Console = @import("Console.zig");
const Screen = @import("Screen.zig");

const Kernel = @This();
const run_logger = std.log.scoped(.run);
const boot_logger = std.log.scoped(.run);

pub extern const KERNEL_END: u32;
pub extern const KERNEL_START: u32;

/// GLOBAL VARIABLES
/// The size of the fixed allocator used before the heap is set up. Set to 2MiB.
pub var fixed_buffer: [1024 * 1024]u8 = undefined;

/// The fixed allocator used before the heap is set up.
pub var fixed_buffer_allocator: std.heap.FixedBufferAllocator = std.heap.FixedBufferAllocator.init(fixed_buffer[0..]);
const fixed_buffer_ally = fixed_buffer_allocator.allocator();

var serial: Serial = undefined;
var serial_writer: Serial.SerialWriter = undefined;

port_manager: PortManager,
ally: Ally,
screen: Screen,
info: *const multiboot.MultibootInfo,
console: Console,

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    serial_writer.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch unreachable;
}

pub fn init(multiboot_magic: u32, info: *const multiboot.MultibootInfo) !Kernel {
    var port_manager = PortManager.init(fixed_buffer_ally);
    serial = try Serial.initialize(&port_manager);
    serial_writer = serial.writer();

    std.log.info("multiboot magic 0x{x}", .{multiboot_magic});

    // must come after serial as it uses log
    std.log.info("initializing panic handler and debug symbols", .{});
    try debug.initSymbols(info.getModules(), fixed_buffer_ally);

    return .{
        .port_manager = port_manager,
        .ally = Ally.init(info),
        .screen = try Screen.initialize(info),
        .info = info,
        .console = Console.initialize(),
    };
}

pub fn run(kernel: *Kernel) !void {
    run_logger.info("Kernel Initialized", .{});
    const kernel_allocator = kernel.ally.allocator();
    var arr_a = try std.ArrayList(u8).initCapacity(kernel_allocator, 2);
    defer arr_a.deinit();

    try arr_a.append(1);
    try arr_a.append(2);
    try arr_a.append(3);
    try arr_a.append(4);
    try arr_a.append(5);
    try arr_a.append(6);

    const testStruct = struct { u32, u32, u32, u128 };

    const ts = try kernel_allocator.create(testStruct);
    defer kernel_allocator.destroy(ts);

    ts.* = .{ 2, 2, 2, 2 };

    run_logger.info("framebuffer_height: {d}", .{kernel.info.framebuffer_height});
    run_logger.info("framebuffer_width: {d}", .{kernel.info.framebuffer_width});
    run_logger.info("framebuffer_bpp: {d}", .{kernel.info.framebuffer_bpp});
    run_logger.info("framebuffer_pitch: {d}", .{kernel.info.framebuffer_pitch});
    run_logger.info("framebuffer_addr: 0x{x}", .{kernel.info.framebuffer_addr});

    kernel.screen.drawCircle(kernel.screen.height / 16, kernel.screen.height / 2, kernel.screen.height / 4, .{ .rgb = .{ .r = 0, .g = 0, .b = 255 } });
    kernel.screen.drawCircle(0, 0, kernel.screen.height / 4, .{ .rgb = .{ .r = 255, .g = 255, .b = 255 } });
    run_logger.info("Circles Drawn", .{});
}
