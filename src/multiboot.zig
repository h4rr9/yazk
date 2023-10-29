pub const MULTIBOOT_MEMORY_AVAILABLE = 1;
pub const MULTIBOOT_MEMORY_RESERVED = 2;

/// A Module
pub const Module = packed struct {
    mod_start: u32,
    mod_end: u32,
    cmdline: [*:0]const u8,
    _: u32 = 0,
};

pub const MultibootInfo = extern struct {
    // Multiboot info version number
    flags: u32,

    // Available memory from BIOS
    mem_lower: u32,
    mem_upper: u32,

    // "root" partition
    boot_device: u32,

    // Kernel command line
    cmdline: u32,

    // Boot-Module list
    mods_count: u32,
    mods_addr: u32,

    dummy: [16]u8,

    // Memory Mapping buffer
    mmap_length: u32,
    mmap_addr: u32,

    // Drive Info buffer
    drives_length: u32,
    drives_addr: u32,

    // ROM configuration table
    config_table: u32,

    // Boot Loader Name
    boot_loader_name: [*:0]const u8,

    // APM table
    apm_table: u32,

    // Video.
    vbe_control_info: u32,
    vbe_mode_info: u32,
    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,

    const Self = @This();

    pub fn getMmapAddrs(self: *const Self) []MultibootMmapEntry {
        const mmaps = @as([*]MultibootMmapEntry, @ptrFromInt(self.mmap_addr));
        return mmaps[0..self.getNumMmap()];
    }

    pub inline fn getNumMmap(self: *const Self) u32 {
        return self.mmap_length / @sizeOf(MultibootMmapEntry);
    }

    pub fn getModules(self: *const Self) []Module {
        return @as([*]Module, @ptrFromInt(self.mods_addr))[0..self.mods_count];
    }
};

pub const MultibootMmapEntry = packed struct {
    size: u32,
    addr: u32,
    _reserved_addr: u32,
    len: u32,
    _reserved_len: u32,
    type: u32,
};
