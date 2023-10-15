const std = @import("std");
const multiboot = @import("multiboot.zig");
const layout = @import("layout.zig");
const console = @import("console.zig");

const Block = struct {
    free: bool,
    prev: ?*Block,
    next: ?*Block,

    prev_free: ?*Block,
    next_free: ?*Block,

    const Self = @This();

    pub fn init() Self {
        return .{
            .free = true,
            .prev = null,
            .next = null,
            .prev_free = null,
            .next_free = null,
        };
    }
};

pub const Allocator = struct {
    first_free: ?*Block,

    const Self = @This();
    pub fn init(info: *const multiboot.MultibootInfo) Self {
        const block = for (info.getMmapAddrs()) |mmap| {
            if (mmap.addr == @intFromPtr(&layout.KERNEL_START)) break mmap;
        } else @panic("failed to find big block of ram.");
        _ = block;

        return .{ .first_free = null };
    }
    fn alloc(
        _: *anyopaque,
        len: usize,
        log2_align: u8,
        return_address: usize,
    ) ?[*]u8 {
        _ = return_address;
        _ = log2_align;
        _ = len;
        console.puts("FOUND ALLOC\n");
        unreachable;
    }
    fn resize(
        _: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        new_len: usize,
        return_address: usize,
    ) bool {
        _ = return_address;
        _ = new_len;
        _ = log2_buf_align;
        _ = buf;

        console.puts("FOUND RESIZE\n");
        unreachable;
    }
    fn free(
        _: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        return_address: usize,
    ) void {
        _ = return_address;
        _ = log2_buf_align;
        _ = buf;
        console.puts("FOUND FREE\n");
        unreachable;
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }
};
