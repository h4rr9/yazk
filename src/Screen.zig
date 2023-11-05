const std = @import("std");
const multiboot = @import("multiboot.zig");

const screen_logger = std.log.scoped(.screen);

const Screen = @This();

buffer: [*]u8,
bytes_per_pixel: u8,
height: u32,
width: u32,
pitch: u32,

const COLOR_MAX: f32 = @floatCast(std.math.maxInt(u8));

///
/// FrameBuffer Errors
///
const ScreenError = error{
    NoFrameBuffer,
    InvalidColorType,
    BitsPerPixelNotByteAligned,
    ColorOffsetNotByteAligned,
};

///
///
///
pub const Color = packed union {
    rgb: packed struct(u32) {
        b: u8,
        g: u8,
        r: u8,
        _: u8 = 0,
    },
    pixel: u32,
};

///
///
///
///
pub fn initialize(info: *const multiboot.MultibootInfo) !Screen {
    if ((info.flags >> 11) & 1 == 0) return ScreenError.NoFrameBuffer;
    if (info.framebuffer_type != 1) return ScreenError.InvalidColorType;

    if (info.framebuffer_bpp % 8 != 0) return ScreenError.BitsPerPixelNotByteAligned;

    const addr: u32 = @truncate(info.framebuffer_addr);

    return .{
        .buffer = @ptrFromInt(addr),
        .bytes_per_pixel = @divExact(info.framebuffer_bpp, 8),
        .height = info.framebuffer_height,
        .width = info.framebuffer_width,
        .pitch = info.framebuffer_pitch,
    };
}

///
/// Convert rgb from 0..1 to 0..255 to Color
///
pub fn convertColor(r: f32, g: f32, b: f32) Color {
    return .{ .rgb = .{
        .r = @intFromFloat(r * COLOR_MAX),
        .g = @intFromFloat(g * COLOR_MAX),
        .b = @intFromFloat(b * COLOR_MAX),
    } };
}

///
/// Compute offset of coordinates from buffer start.
///
inline fn offsetXY(screen: *const Screen, x: u32, y: u32) u32 {
    return x * screen.pitch + y * @as(u32, @intCast(screen.bytes_per_pixel));
}

///
///
///
///
pub fn setPixel(screen: *const Screen, row: u32, col: u32, color: Color) void {
    const offset = screen.offsetXY(row, col);
    const pixel_ptr: *u32 = @ptrCast(@alignCast(&screen.buffer[offset]));
    pixel_ptr.* = color.pixel;
}

pub fn drawCircle(screen: *const Screen, x: u32, y: u32, r: u32, c: Color) void {
    const x_start = if (x <= r) 0 else x - r;
    const x_end = @min(x + r, screen.width - 1);
    const y_start = if (y <= r) 0 else y - r;
    const y_end = @min(y + r, screen.height - 1);

    var x_delta: u32 = x_start;
    std.log.info("xs: {d}, xe: {d}, ys: {d}, ye: {d}", .{ x_start, x_end, y_start, y_end });

    while (x_delta <= x_end) : (x_delta += 1) {
        var y_delta: u32 = y_start;
        while (y_delta <= y_end) : (y_delta += 1) {
            const dx2: u32 = @intCast(std.math.powi(i64, @as(i64, x_delta) - @as(i64, x), 2) catch unreachable);
            const dy2: u32 = @intCast(std.math.powi(i64, @as(i64, y_delta) - @as(i64, y), 2) catch unreachable);
            if (dx2 + dy2 <= r * r) screen.setPixel(y_delta, x_delta, c);
        }
    }
}
