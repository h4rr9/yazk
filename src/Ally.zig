const std = @import("std");
const multiboot = @import("multiboot.zig");
const Kernel = @import("Kernel.zig");

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
        if (mmap.addr == @intFromPtr(&Kernel.KERNEL_START))
            if (mmap.type == multiboot.MULTIBOOT_MEMORY_AVAILABLE)
                break mmap;
    } else @panic("failed to find big block of ram.");
    const kernel_end: u32 = @intFromPtr(&Kernel.KERNEL_END);
    const kernel_start: u32 = @intFromPtr(&Kernel.KERNEL_START);
    const reserved_memory_length: u32 = kernel_end - kernel_start;

    const segment_size = block.len - reserved_memory_length - @sizeOf(FreeSegment);

    const segment: *FreeSegment = @ptrCast(@alignCast(&Kernel.KERNEL_END));
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

// ######## ALLOC TESTS ########

fn allocState(ally: *Ally) [100]FreeSegment {
    var segments: [100]FreeSegment = [_]FreeSegment{.{ .size = 0, .next_segment = null }} ** 100;
    var it: u32 = 0;
    var free_block = ally.first_free;
    while (free_block) |free_blk| : (free_block = free_blk.next_segment) {
        segments[it] = free_blk.*;
        it += 1;
    }
    return segments;
}

fn setupAlloc(chunk: [*]u8, len: u32) Ally {
    @setRuntimeSafety(false);
    const segment: *FreeSegment = @ptrCast(@alignCast(chunk));
    segment.* = .{ .size = len - @sizeOf(FreeSegment), .next_segment = null };
    return .{ .first_free = segment };
}

fn expectNotEqual(comptime T: type, a: T, b: T) !void {
    if (isEqual(T, a, b)) {
        try std.testing.expect(false);
    }
}

fn isEqual(comptime T: type, a: T, b: T) bool {
    for (a, b) |it_a, it_b| {
        if (it_a.next_segment != it_b.next_segment or it_a.size != it_b.size) return false;
    }
    return true;
}

test "Segment Sizes" {
    try std.testing.expectEqual(@sizeOf(FreeSegment), @sizeOf(UsedSegment));
}

test "Simple Alloc" {
    var talloc = std.testing.allocator;

    var chunk = try talloc.alloc(u8, 2 * 1024 * 1024);
    defer talloc.free(chunk);

    var kally = setupAlloc(@ptrCast(&chunk[0]), chunk.len);
    var kalloc = kally.allocator();

    const initial_state = allocState(&kally);
    try std.testing.expectEqual(initial_state.len, 100);

    const p = try kalloc.create(u32);
    p.* = 4;

    const next_state = allocState(&kally);

    try expectNotEqual([100]FreeSegment, initial_state, next_state);

    var n_diff: u32 = 0;

    for (initial_state, next_state) |state_a, state_b| {
        if (state_a.size != state_b.size or state_a.next_segment != state_b.next_segment) {
            n_diff += 1;
        }
    }
    try std.testing.expectEqual(n_diff, 1);

    const diff_seg_a, const diff_seg_b = for (initial_state, next_state) |state_a, state_b| {
        if (state_a.size != state_b.size or state_a.next_segment != state_b.next_segment) {
            break .{ &state_a, &state_b };
        }
    } else @panic("could not find diff items!");

    try std.testing.expect(diff_seg_a.size >= diff_seg_b.size + @sizeOf(@TypeOf(p)) + @sizeOf(UsedSegment));

    kalloc.destroy(p);
    const final_state = allocState(&kally);
    try std.testing.expectEqualSlices(FreeSegment, &initial_state, &final_state);
}

test "Nested Vectors" {
    var talloc = std.testing.allocator;

    var chunk = try talloc.alloc(u8, 2 * 1024 * 1024);
    defer talloc.free(chunk);

    var kally = setupAlloc(@ptrCast(&chunk[0]), chunk.len);
    const kalloc = kally.allocator();

    const initial_state = allocState(&kally);
    {
        var v = std.ArrayList(std.ArrayList(u32)).init(kalloc);
        defer {
            for (v.items) |itm| itm.deinit();
            v.deinit();
        }
        const num_allocations: u32 = 10;

        for (1..num_allocations) |i| {
            var v2 = std.ArrayList(u32).init(kalloc);
            for (0..i) |j| {
                try v2.append(j);
            }
            try v.append(v2);
        }

        // remove all even elements and deinit them.
        var idx: u32 = num_allocations;
        while (idx > 0) {
            idx -= 1;
            if (idx % 2 == 0) {
                const len = v.items.len - 1;

                // swap values
                const tmp = v.items[len];
                v.items[len] = v.items[idx];
                v.items[idx] = tmp;

                // pop
                var arr = v.pop();
                arr.deinit();
            }
        }

        {
            var v3 = std.ArrayList(std.ArrayList(u32)).init(kalloc);
            defer {
                for (v3.items) |itm| itm.deinit();
                v3.deinit();
            }

            for (1..num_allocations) |i| {
                var v2 = std.ArrayList(u32).init(kalloc);
                for (0..i) |j| {
                    try v2.append(j);
                }
                try v3.append(v2);
            }
        }

        // memory corruption

        for (v.items) |elem|
            for (elem.items, 0..) |item, i| {
                try std.testing.expectEqual(i, item);
            };
    }

    const final_state = allocState(&kally);
    try std.testing.expectEqualSlices(FreeSegment, &initial_state, &final_state);
}
