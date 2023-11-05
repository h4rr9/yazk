const std = @import("std");

allocated_ports: std.AutoHashMap(u16, void),

const PortManager = @This();

pub fn init(alloc: std.mem.Allocator) PortManager {
    return .{
        .allocated_ports = std.AutoHashMap(u16, void).init(alloc),
    };
}

pub fn requestPort(port_manager: *PortManager, addr: u16) !?Port {
    const result = try port_manager.allocated_ports.getOrPut(addr);
    return if (result.found_existing) null else .{ .addr = addr };
}

pub const Port = struct {
    addr: u16,

    pub fn writeb(self: *const Port, val: u8) void {
        const addr = self.addr;
        asm volatile ("outb %al, %dx"
            :
            : [addr] "{dx}" (addr),
              [val] "{al}" (val),
            : "memory"
        );
    }

    pub fn readb(self: *const Port) u8 {
        const addr = self.addr;
        return asm volatile ("inb %dx, %al"
            : [ret] "={al}" (-> u8),
            : [addr] "{dx}" (addr),
            : "memory"
        );
    }
};
