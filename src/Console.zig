const Self = @This();

const fmt = @import("std").fmt;
const mem = @import("std").mem;
const Writer = @import("std").io.Writer;

const VGA_WIDTH = 80;
const VGA_HEIGHT = 25;
const VGA_SIZE = VGA_WIDTH * VGA_HEIGHT;

const Console = @This();

pub const ConsoleColors = enum(u8) {
    Black = 0,
    Blue = 1,
    Green = 2,
    Cyan = 3,
    Red = 4,
    Magenta = 5,
    Brown = 6,
    LightGray = 7,
    DarkGray = 8,
    LightBlue = 9,
    LightGreen = 10,
    LightCyan = 11,
    LightRed = 12,
    LightMagenta = 13,
    LightBrown = 14,
    White = 15,
};

row: u32,
column: u32,
color: u8,
buffer: [*]volatile u16,

fn vgaEntryColor(fg: ConsoleColors, bg: ConsoleColors) u8 {
    return @intFromEnum(fg) | (@intFromEnum(bg) << 4);
}

fn vgaEntry(console: *Console, uc: u8) u16 {
    var c: u16 = console.color;
    return uc | (c << 8);
}

pub fn initialize() Console {
    var console: Console = .{
        .row = 0,
        .column = 0,
        .color = vgaEntryColor(.White, .Black),
        .buffer = @as([*]volatile u16, @ptrFromInt(0xB8000)),
    };
    console.clear();
    return console;
}

pub fn setColor(console: *Console, new_color: u8) void {
    console.color = new_color;
}

pub fn clear(console: *Console) void {
    @memset(console.buffer[0..VGA_SIZE], console.vgaEntry(' '));
}

fn putCharHelper(console: *Console, c: u8) void {
    const index = console.row * VGA_WIDTH + console.column;
    console.buffer[index] = console.vgaEntry(c);
}

pub fn putChar(console: *Console, c: u8) void {
    if (c == '\n') {
        console.column = 0;
        console.row += 1;
        if (console.row == VGA_HEIGHT) {
            console.row = 0;
        }
    } else {
        console.putCharHelper(c);
        console.column += 1;
        if (console.column == VGA_WIDTH) {
            console.column = 0;
            console.row += 1;
            if (console.row == VGA_HEIGHT) {
                console.row = 0;
            }
        }
    }
}

pub fn puts(console: *Console, data: []const u8) void {
    for (data) |c| console.putChar(c);
}

const ConsoleWriter = Writer(
    *Console,
    error{},
    struct {
        pub fn writeFn(console: *Console, string: []const u8) error{}!u32 {
            console.puts(string);
            return string.len;
        }
    }.writeFn,
);

pub fn writer(console: *Console) ConsoleWriter {
    return ConsoleWriter{ .context = console };
}
