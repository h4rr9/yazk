const std = @import("std");
const Writer = @import("std").io.Writer;
const fmt = @import("std").fmt;

const COM1 = 0x3f8;

pub fn initialize() u32 {
    outb(COM1 + 1, 0x00); // Disable all interrupts
    outb(COM1 + 3, 0x80); // Enable DLAB (set baud rate divisor)
    outb(COM1 + 0, 0x03); // Set divisor to 3 (lo byte) 38400 baud
    outb(COM1 + 1, 0x00); //                  (hi byte)
    outb(COM1 + 3, 0x03); // 8 bits, no parity, one stop bit
    outb(COM1 + 2, 0xC7); // Enable FIFO, clear them, with 14-byte threshold
    outb(COM1 + 4, 0x0B); // IRQs enabled, RTS/DSR set
    outb(COM1 + 4, 0x1E); // Set in loopback mode, test the serial chip
    outb(COM1 + 0, 0xAE); // Test serial chip (send byte 0xAE and check if serial returns same byte)

    // Check if serial is faulty (i.e: not same byte as sent)
    if (inb(COM1 + 0) != 0xAE) {
        return 1;
    }

    // If serial is not faulty set it in normal operation mode
    // (not-loopback with IRQs enabled and OUT#1 and OUT#2 bits enabled)
    outb(COM1 + 4, 0x0F);
    return 0;
}

fn serialReceived() u8 {
    return inb(COM1 + 5) & 1;
}

pub fn readSerial() u8 {
    while (serialReceived() == 0) {}
    return inb(COM1);
}

fn isTransmitEmpty() u32 {
    return inb(COM1 + 5) & 0x20;
}

pub fn writeSerial(a: u8) void {
    while (isTransmitEmpty() == 0) {}
    outb(COM1, a);
}

fn outb(port: u16, val: u8) void {
    asm volatile ("outb %al, %dx"
        :
        : [port] "{dx}" (port),
          [val] "{al}" (val),
        : "memory"
    );
}

fn inb(port: u16) u8 {
    return asm volatile ("inb %dx, %al"
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
        : "memory"
    );
}

pub fn puts(data: []const u8) void {
    for (data) |c| writeSerial(c);
}

pub const writer = Writer(void, error{}, callback){ .context = {} };

fn callback(_: void, string: []const u8) error{}!u32 {
    puts(string);
    return string.len;
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    fmt.format(writer, format, args) catch unreachable;
}
