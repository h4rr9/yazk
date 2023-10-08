const std = @import("std");

const console = @import("console.zig");

const ALIGN = 1 << 0; // 0000 0001 - one left shift zero
const MEMINFO = 1 << 1; // 0000 0010 - one left shift 1
const MAGIC = 0x1BADB002; // GRUB magic
const FLAGS = ALIGN | MEMINFO;
const MultibootHeader = extern struct { magic: i32 = MAGIC, flags: i32, checksum: i32 };

export var _ align(4) linksection(".multiboot") = MultibootHeader{
    .flags = FLAGS,
    .checksum = -(MAGIC + FLAGS),
};

export fn _start() align(4) linksection(".text") callconv(.C) void {
    @call(.auto, kmain, .{});
    while (true) std.atomic.spinLoopHint();
}

export fn kmain() void {
    console.initialize();
    console.puts("Hello world!\nAnother World!");
}
