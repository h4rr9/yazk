const std = @import("std");
const multiboot = @import("multiboot.zig");
const layout = @import("layout.zig");
const console = @import("console.zig");
const assert = std.debug.assert;

const FreeSegment = packed struct {
    size: u32,
    next_segment: ?*FreeSegment,

    pub fn getStart(self: *FreeSegment) [*]u8 {
        const ptr: [*]u8 = @ptrFromInt(@intFromPtr(self) + @sizeOf(FreeSegment));
        return @ptrCast(@alignCast(ptr));
    }

    pub fn getEnd(self: *FreeSegment) [*]u8 {
        return self.getStart() + self.size;
    }

    pub fn setEnd(self: *FreeSegment, end: [*]u8) void {
        self.size = @intFromPtr(end) - @intFromPtr(self.getStart());
    }
};

const UsedSegment = packed struct {
    size: usize,
    next_segment: ?*UsedSegment,

    pub fn getStart(self: *UsedSegment) [*]u8 {
        const ptr: [*]u8 = @ptrFromInt(@intFromPtr(self) + @sizeOf(UsedSegment));
        return @ptrCast(@alignCast(ptr));
    }

    pub fn setEnd(self: *UsedSegment, end: *u8) void {
        self.size = @intFromPtr(end) - @intFromPtr(self.getStart());
    }
};

first_free: ?*FreeSegment,

// ###### Zig allocator Interface #########

const Ally = @This();

pub fn init(info: *const multiboot.MultibootInfo) Ally {
    const block = for (info.getMmapAddrs()) |mmap| {
        if (mmap.addr == @intFromPtr(&layout.KERNEL_START))
            if (mmap.type == multiboot.MULTIBOOT_MEMORY_AVAILABLE)
                break mmap;
    } else @panic("failed to find big block of ram.");
    const kernel_end: u32 = @intFromPtr(&layout.KERNEL_END);
    const kernel_start: u32 = @intFromPtr(&layout.KERNEL_START);
    const reserverd_memory_length: u32 = kernel_end - kernel_start;

    const segment_size = block.len - reserverd_memory_length - @sizeOf(FreeSegment);

    const segment: *FreeSegment = @ptrCast(@alignCast(&layout.KERNEL_END));
    segment.* = .{ .size = segment_size, .next_segment = null };

    return .{ .first_free = segment };
}

fn alloc(ctx: *anyopaque, len: usize, log2_align: u8, _: usize) ?[*]u8 {
    const self: *Ally = @ptrCast(@alignCast(ctx));
    const ptr_align = @as(usize, 1) << @as(std.mem.Allocator.Log2Align, @intCast(log2_align));

    var free_block = self.first_free;
    var i: usize = 0;

    return while (free_block) |free_blk| : (free_block = free_blk.next_segment) {

        // find header for allocation
        const segment_end: [*]u8 = free_blk.getEnd();
        var ptr: [*]u8 = segment_end - len;

        ptr -= @intFromPtr(ptr) % ptr_align;
        ptr -= @sizeOf(UsedSegment);

        if (@intFromPtr(ptr) >= @intFromPtr(free_blk.getStart())) {
            @setRuntimeSafety(false);
            const used_end = segment_end;
            free_blk.setEnd(ptr);

            var used_blk: *UsedSegment = @ptrCast(@alignCast(ptr));
            used_blk.setEnd(@ptrCast(used_end));

            break used_blk.getStart();
        }
        i += 1;
    } else return null;
}

/// TODO implement resize
fn resize(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, _: usize) bool {
    _ = new_len;
    _ = log2_buf_align;
    _ = buf;
    _ = ctx;

    return false;
}

fn free(ctx: *anyopaque, buf: []u8, log2_align: u8, _: usize) void {
    _ = log2_align;
    const self: *Ally = @ptrCast(@alignCast(ctx));

    @setRuntimeSafety(false);
    const ptr: [*]u8 = @ptrCast(&buf[0]);
    const used_ptr: *UsedSegment = @ptrCast(@alignCast(ptr - @sizeOf(UsedSegment)));
    const size = used_ptr.size;

    const free_ptr: *FreeSegment = @ptrCast(@alignCast(used_ptr));
    free_ptr.size = size;
    free_ptr.next_segment = null;

    @setRuntimeSafety(true);

    var free_block = self.first_free;
    while (free_block) |free_blk| : (free_block = free_blk.next_segment) {
        assert(@intFromPtr(free_blk) < @intFromPtr(free_ptr));

        const should_insert: bool = if (free_blk.next_segment) |nxt_seg|
            @intFromPtr(nxt_seg) > @intFromPtr(free_ptr)
        else
            true;

        if (should_insert) {
            const next = free_blk.next_segment;
            free_blk.next_segment = free_ptr;
            free_ptr.next_segment = next;

            mergeIfAdjacent(free_ptr, free_ptr.next_segment);
            mergeIfAdjacent(free_blk, free_ptr);

            break;
        }
    } else {
        @panic("Failed to insert free block into free list");
    }
}

fn mergeIfAdjacent(a: *FreeSegment, b: ?*FreeSegment) void {
    if (b) |free_b| {
        if (@intFromPtr(a.getEnd()) == @intFromPtr(free_b)) {
            a.setEnd(free_b.getEnd());
            a.next_segment = free_b.next_segment;
        }
    }
}

pub fn allocator(self: *Ally) std.mem.Allocator {
    return std.mem.Allocator{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .free = free,
        },
    };
}

test "Segment Sizes" {
    try std.testing.expectEqual(@sizeOf(FreeSegment), @sizeOf(UsedSegment));
}
