/// yoinked from https://github.com/ZystemOS/pluto/blob/develop/src/kernel/panic.zig
const std = @import("std");
const builtin = std.builtin;
const Console = @import("Console.zig");
const multiboot = @import("multiboot.zig");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

/// The possible errors from panic code
const PanicError = error{
    /// The symbol file is of an invalid format.
    /// This could be because it lacks whitespace, a column or required newline characters.
    InvalidSymbolFile,
};

/// An entry within a symbol map. Corresponds to one entry in a symbol file
const MapEntry = struct {
    /// The address that the entry corresponds to
    addr: u32,

    /// The name of the function that starts at the address
    func_name: []const u8,
};

const SymbolMap = struct {
    symbols: ArrayList(MapEntry),

    ///
    /// Initialise an empty symbol map.
    ///
    /// Arguments:
    ///     IN allocator: Allocator - The allocator to use to initialise the array list.
    ///
    /// Return: SymbolMap
    ///     The symbol map.
    ///
    pub fn init(allocator: Allocator) SymbolMap {
        return SymbolMap{
            .symbols = ArrayList(MapEntry).init(allocator),
        };
    }

    ///
    /// Deinitialise the symbol map, freeing all memory used.
    ///
    pub fn deinit(self: *SymbolMap) void {
        self.symbols.deinit();
    }

    ///
    /// Add a symbol map entry.
    ///
    /// Arguments:
    ///     IN entry: MapEntry - The entry.
    ///
    /// Error: Allocator.Error
    ///      error.OutOfmemory - If there isn't enough memory to append a map entry.
    ///
    pub fn addEntry(self: *SymbolMap, entry: MapEntry) Allocator.Error!void {
        try self.symbols.append(entry);
    }

    ///
    /// Search for the function name associated with the address.
    ///
    /// Arguments:
    ///     IN addr: u32 - The address to search for.
    ///
    /// Return: ?[]const u8
    ///     The function name associated with that program address, or null if one wasn't found.
    ///
    pub fn search(self: *const SymbolMap, addr: u32) ?[]const u8 {
        if (self.symbols.items.len == 0)
            return null;
        // Find the first element whose address is greater than addr
        var previous_name: ?[]const u8 = null;
        for (self.symbols.items) |entry| {
            if (entry.addr > addr)
                return previous_name;
            previous_name = entry.func_name;
        }
        return previous_name;
    }
};

var symbol_map: ?SymbolMap = null;

///
/// Log a stacktrace address. Logs "(no symbols are available)" if no symbols are available,
/// "?????" if the address wasn't found in the symbol map, else logs the function name.
///
/// Arguments:
///     IN addr: u32 - The address to log.
///
fn logTraceAddress(addr: u32) void {
    const str = if (symbol_map) |syms| syms.search(addr) orelse "?????" else "(no symbols available)";
    std.log.err("{x}: {s}", .{ addr, str });
}

///
/// Parse a hexadecimal address from the pointer up until the end pointer. Must be terminated by a
/// whitespace character.
///
/// Arguments:
///     IN/OUT ptr: *[*]const u8 - The address at which to start looking, updated after all
///         characters have been consumed.
///     IN end: *const u8 - The end address at which to start looking. A whitespace character must
///         be found before this.
///
/// Return: u32
///     The address parsed.
///
/// Error: PanicError || std.fmt.ParseIntError
///     PanicError.InvalidSymbolFile - A terminating whitespace wasn't found before the end address.
///     std.fmt.ParseIntError - See std.fmt.parseInt
///
fn parseAddr(ptr: *[*]const u8, end: *const u8) (PanicError || std.fmt.ParseIntError)!u32 {
    const addr_start = ptr.*;
    ptr.* = try parseNonWhitespace(ptr.*, end);
    const len = @intFromPtr(ptr.*) - @intFromPtr(addr_start);
    const addr_str = addr_start[0..len];
    return std.fmt.parseInt(u32, addr_str, 16);
}

///
/// Parse a single character. The address given cannot be greater than or equal to the end address
/// given.
///
/// Arguments:
///     IN ptr: [*]const u8 - The address at which to get the character from.
///     IN end: *const u8 - The end address at which to start looking. ptr cannot be greater than or
///         equal to this.
///
/// Return: u8
///     The character parsed.
///
/// Error: PanicError
///     PanicError.InvalidSymbolFile - The address given is greater than or equal to the end address.
///
fn parseChar(ptr: [*]const u8, end: *const u8) PanicError!u8 {
    if (@intFromPtr(ptr) >= @intFromPtr(end)) {
        return PanicError.InvalidSymbolFile;
    }
    return ptr[0];
}

///
/// Parse until a non-whitespace character. Must be terminated by a non-whitespace character before
/// the end address.
///
/// Arguments:
///     IN ptr: [*]const u8 - The address at which to start looking.
///     IN end: *const u8 - The end address at which to start looking. A non-whitespace character
///         must be found before this.
///
/// Return: [*]const u8
///     ptr plus the number of whitespace characters consumed.
///
/// Error: PanicError
///     PanicError.InvalidSymbolFile - A terminating non-whitespace character wasn't found before
///         the end address.
///
fn parseWhitespace(ptr: [*]const u8, end: *const u8) PanicError![*]const u8 {
    var i: u32 = 0;
    while (std.ascii.isWhitespace(try parseChar(ptr + i, end))) : (i += 1) {}
    return ptr + i;
}

///
/// Parse until a whitespace character. Must be terminated by a whitespace character before the end
/// address.
///
/// Arguments:
///     IN ptr: [*]const u8 - The address at which to start looking.
///     IN end: *const u8 - The end address at which to start looking. A whitespace character must
///         be found before this.
///
/// Return: [*]const u8
///     ptr plus the number of non-whitespace characters consumed.
///
/// Error: PanicError
///     PanicError.InvalidSymbolFile - A terminating whitespace character wasn't found before the
///         end address.
///
fn parseNonWhitespace(ptr: [*]const u8, end: *const u8) PanicError![*]const u8 {
    var i: u32 = 0;
    while (!std.ascii.isWhitespace(try parseChar(ptr + i, end))) : (i += 1) {}
    return ptr + i;
}

///
/// Parse until a newline character. Must be terminated by a newline character before the end
/// address.
///
/// Arguments:
///     IN ptr: [*]const u8 - The address at which to start looking.
///     IN end: *const u8 - The end address at which to start looking. A newline character must
///         be found before this.
///
/// Return: [*]const u8
///     ptr plus the number of non-newline characters consumed.
///
/// Error: PanicError
///     PanicError.InvalidSymbolFile - A terminating newline character wasn't found before the
///         end address.
///
fn parseNonNewLine(ptr: [*]const u8, end: *const u8) PanicError![*]const u8 {
    var i: u32 = 0;
    while ((try parseChar(ptr + i, end)) != '\n') : (i += 1) {}
    return ptr + i;
}

///
/// Parse a name from the pointer up until the end pointer. Must be terminated by a whitespace
/// character.
///
/// Arguments:
///     IN/OUT ptr: *[*]const u8 - The address at which to start looking, updated after all
///         characters have been consumed.
///     IN end: *const u8 - The end address at which to start looking. A whitespace character must
///         be found before this.
///
/// Return: []const u8
///     The name parsed.
///
/// Error: PanicError
///     PanicError.InvalidSymbolFile - A terminating whitespace wasn't found before the end address.
///
fn parseName(ptr: *[*]const u8, end: *const u8) PanicError![]const u8 {
    const name_start = ptr.*;
    ptr.* = try parseNonNewLine(ptr.*, end);
    const len = @intFromPtr(ptr.*) - @intFromPtr(name_start);
    return name_start[0..len];
}

///
/// Parse a symbol map entry from the pointer up until the end pointer,
/// in the format of '\d+\w+[a-zA-Z0-9]+'. Must be terminated by a whitespace character.
///
/// Arguments:
///     IN/OUT ptr: *[*]const u8 - The address at which to start looking, updated once after the
///         address has been consumed and once again after the name has been consumed.
///     IN end: *const u8 - The end address at which to start looking. A whitespace character must
///         be found before this.
///
/// Return: MapEntry
///     The entry parsed.
///
/// Error: PanicError || std.fmt.ParseIntError
///     PanicError.InvalidSymbolFile - A terminating whitespace wasn't found before the end address.
///     std.fmt.ParseIntError - See parseAddr.
///
fn parseMapEntry(start: *[*]const u8, end: *const u8) (PanicError || std.fmt.ParseIntError)!MapEntry {
    var ptr = try parseWhitespace(start.*, end);
    defer start.* = ptr;
    const addr = try parseAddr(&ptr, end);
    ptr = try parseWhitespace(ptr, end);
    const name = try parseName(&ptr, end);
    return MapEntry{ .addr = addr, .func_name = name };
}

var already_panicking: bool = false;

pub fn panic(trace: ?*builtin.StackTrace, return_addr: ?u32, comptime format: []const u8, args: anytype) noreturn {
    @setCold(true);
    if (already_panicking) {
        std.log.err("\npanicked during kernel panic", .{});
    } else {
        already_panicking = true;
        std.log.err("Kernel panic: " ++ format, args);
        if (trace) |trc| {
            var last_addr: u64 = 0;
            for (trc.instruction_addresses) |ret_addr| {
                if (ret_addr != last_addr) logTraceAddress(ret_addr);
                last_addr = ret_addr;
            }
        } else {
            const first_ret_addr = return_addr;
            var last_addr: u64 = 0;
            var it = std.debug.StackIterator.init(first_ret_addr, null);
            while (it.next()) |ret_addr| {
                if (ret_addr != last_addr) logTraceAddress(ret_addr);
                last_addr = ret_addr;
            }
        }
    }

    while (true) std.atomic.spinLoopHint();
}

///
/// Initialise the symbol table used by the panic subsystem by looking for a boot module called "kernel.map" and loading the
/// symbol entries from it. Exits early if no such module was found.
///
/// Arguments:
///     IN mem_profile: *const mem.MemProfile - The memory profile from which to get the loaded boot
///         modules.
///     IN allocator: Allocator - The allocator to use to store the symbol map.
///
/// Error: PanicError || Allocator.Error || std.fmt.ParseIntError
///     PanicError.InvalidSymbolFile - A terminating whitespace wasn't found before the end address.
///     Allocator.Error.OutOfMemory - If there wasn't enough memory.
///     std.fmt.ParseIntError - See parseMapEntry.
///
pub fn initSymbols(modules: []multiboot.Module, allocator: Allocator) !void {

    // Exit if we haven't loaded all debug modules
    if (modules.len < 1) {
        return;
    }

    var kmap_start: u32 = 0;
    var kmap_end: u32 = 0;
    for (modules) |module| {
        const mod_start = module.mod_start;
        const mod_end = module.mod_end - 1;
        if (std.mem.eql(u8, std.mem.span(module.cmdline), "kernel.map")) {
            kmap_start = mod_start;
            kmap_end = mod_end;
            break;
        }
    }
    // Don't try to load the symbols if there was no symbol map file. This is a valid state so just
    // exit early
    if (kmap_start == 0 or kmap_end == 0) {
        return;
    }

    var syms = SymbolMap.init(allocator);
    errdefer syms.deinit();
    var kmap_ptr = @as([*]u8, @ptrFromInt(kmap_start));
    while (@intFromPtr(kmap_ptr) < kmap_end - 1) {
        const entry = try parseMapEntry(&kmap_ptr, @as(*const u8, @ptrFromInt(kmap_end)));
        try syms.addEntry(entry);
    }
    symbol_map = syms;
}
