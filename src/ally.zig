const std = @import("std");
const multiboot = @import("multiboot.zig");
const layout = @import("layout.zig");

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
    size: u32,
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
    const reserved_memory_length: u32 = kernel_end - kernel_start;

    const segment_size = block.len - reserved_memory_length - @sizeOf(FreeSegment);

    const segment: *FreeSegment = @ptrCast(@alignCast(&layout.KERNEL_END));
    segment.* = .{ .size = segment_size, .next_segment = null };

    return .{ .first_free = segment };
}

fn alloc(ctx: *anyopaque, len: u32, log2_align: u8, _: u32) ?[*]u8 {
    const self: *Ally = @ptrCast(@alignCast(ctx));
    const ptr_align = @as(u32, 1) << @as(std.mem.Allocator.Log2Align, @intCast(log2_align));

    var free_block = self.first_free;
    var i: u32 = 0;

    while (free_block) |free_blk| : (free_block = free_blk.next_segment) {

        // find header for allocation
        const segment_end: [*]u8 = free_blk.getEnd();
        var ptr: [*]u8 = segment_end - len;

        // calculate alignment offset to substract
        const align_offset = std.mem.alignPointerOffset(ptr, ptr_align) orelse @panic("SOMETHING WENT WRONG!");
        ptr -= ptr_align - align_offset;

        // offset by size of node header
        ptr -= @sizeOf(UsedSegment);

        if (@intFromPtr(ptr) >= @intFromPtr(free_blk.getStart())) {
            // disable safety for pointer cast
            @setRuntimeSafety(false);
            // grab end of used_block
            const used_end = segment_end;

            // set free block end to header of used block
            free_blk.setEnd(ptr);

            // update used block size
            var used_blk: *UsedSegment = @ptrCast(@alignCast(ptr));
            used_blk.setEnd(@ptrCast(used_end));

            // return used block
            return used_blk.getStart();
        }
        i += 1;
    } else return null;
}

fn resize(ctx: *anyopaque, buf: []u8, _: u8, new_len: u32, _: u32) bool {
    const self: *Ally = @ptrCast(@alignCast(ctx));

    // disable safety for pointer cast
    @setRuntimeSafety(false);

    // slice to many iterm pointer
    const ptr: [*]u8 = @ptrCast(&buf[0]);

    // cast used block and record data
    const used_ptr: *UsedSegment = @ptrCast(@alignCast(ptr - @sizeOf(UsedSegment)));
    const size = used_ptr.size;

    // make sure new_size can fit FreeSegment
    // and is not empty after the fact.
    const new_size, const overflow_flag = @subWithOverflow(size, new_len + @sizeOf(FreeSegment));
    if (overflow_flag == 0 and new_size > 0) {
        // get free block header start and update used_block size
        const new_ptr = used_ptr.getStart() + new_len;
        used_ptr.setEnd(@ptrCast(new_ptr));

        // create free block
        const free_ptr: *FreeSegment = @ptrCast(@alignCast(new_ptr));
        free_ptr.size = new_size;
        free_ptr.next_segment = null;

        // insert free block into list
        self.insertFreeSegment(free_ptr);

        return true;
    } else {
        return false;
    }
}

fn free(ctx: *anyopaque, buf: []u8, _: u8, _: u32) void {
    const self: *Ally = @ptrCast(@alignCast(ctx));

    // disable safety for pointer cast
    @setRuntimeSafety(false);

    // slice to many iterm pointer
    const ptr: [*]u8 = @ptrCast(&buf[0]);

    // cast used block and record data
    const used_ptr: *UsedSegment = @ptrCast(@alignCast(ptr - @sizeOf(UsedSegment)));
    const size = used_ptr.size;

    // create free block
    const free_ptr: *FreeSegment = @ptrCast(@alignCast(used_ptr));
    free_ptr.size = size;
    free_ptr.next_segment = null;

    // insert free
    self.insertFreeSegment(free_ptr);
}

fn insertFreeSegment(self: *Ally, free_seg: *FreeSegment) void {
    @setRuntimeSafety(true);
    var free_block = self.first_free;
    while (free_block) |free_blk| : (free_block = free_blk.next_segment) {
        const should_insert: bool = if (free_blk.next_segment) |nxt_seg|
            @intFromPtr(nxt_seg) > @intFromPtr(free_seg)
        else
            true;

        if (should_insert) {
            const next = free_blk.next_segment;
            free_blk.next_segment = free_seg;
            free_seg.next_segment = next;

            mergeIfAdjacent(free_seg, free_seg.next_segment);
            mergeIfAdjacent(free_blk, free_seg);

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
