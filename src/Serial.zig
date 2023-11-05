const std = @import("std");
const Writer = @import("std").io.Writer;
const fmt = @import("std").fmt;
const PortManager = @import("PortManager.zig");
const Port = PortManager.Port;

const BASE_ADDR = 0x3f8;

const Serial = @This();

const SerialError = error{
    DataReserved,
    EnableInterruptReserved,
    InterruptIdReserved,
    LineControlReserved,
    ModemControlReserved,
    LineStatusReserved,
    ModemStatusReserved,
    ScratchReserved,
    LoopbackTestFailed,
};

data: Port,
_enable_interrupt: Port,
_interrupt_id_fifo_control: Port,
_line_control: Port,
_model_control: Port,
line_status: Port,
_model_status: Port,
_scratch: Port,

pub fn initialize(port_manager: *PortManager) !Serial {
    var data = try port_manager.requestPort(BASE_ADDR) orelse return SerialError.DataReserved;
    var enable_interrupt = try port_manager.requestPort(BASE_ADDR + 1) orelse return SerialError.EnableInterruptReserved;
    var interrupt_id_fifo_control = try port_manager.requestPort(BASE_ADDR + 2) orelse return SerialError.InterruptIdReserved;
    var line_control = try port_manager.requestPort(BASE_ADDR + 3) orelse return SerialError.LineControlReserved;
    var model_control = try port_manager.requestPort(BASE_ADDR + 4) orelse return SerialError.ModemControlReserved;
    var line_status = try port_manager.requestPort(BASE_ADDR + 5) orelse return SerialError.LineStatusReserved;
    var model_status = try port_manager.requestPort(BASE_ADDR + 6) orelse return SerialError.ModemStatusReserved;
    var scratch = try port_manager.requestPort(BASE_ADDR + 7) orelse return SerialError.ScratchReserved;

    enable_interrupt.writeb(0x00); // Disable all interrupts
    line_control.writeb(0x80); // Enable DLAB (set baud rate divisor)
    data.writeb(0x03); // Set divisor to 3 (lo byte) 38400 baud
    enable_interrupt.writeb(0x00); //                  (hi byte)
    line_control.writeb(0x03); // 8 bits, no parity, one stop bit
    interrupt_id_fifo_control.writeb(0xC7); // Enable FIFO, clear them, with 14-byte threshold
    model_control.writeb(0x0B); // IRQs enabled, RTS/DSR set
    model_control.writeb(0x1E); // Set in loopback mode, test the serial chip
    data.writeb(0xAE); // Test serial chip (send byte 0xAE and check if serial returns same byte)

    // Check if serial is faulty (i.e: not same byte as sent)
    if (data.readb() != 0xAE) {
        return SerialError.LoopbackTestFailed;
    }

    // If serial is not faulty set it in normal operation mode
    // (not-loopback with IRQs enabled and OUT#1 and OUT#2 bits enabled)
    model_control.writeb(0x0F);
    return .{
        .data = data,
        ._enable_interrupt = enable_interrupt,
        ._interrupt_id_fifo_control = interrupt_id_fifo_control,
        ._line_control = line_control,
        ._model_control = model_control,
        .line_status = line_status,
        ._model_status = model_status,
        ._scratch = scratch,
    };
}

fn serialReceived(self: *const Serial) u8 {
    return self.line_status.readb() & 1;
}

pub fn readSerial(self: *const Serial) u8 {
    while (serialReceived() == 0) {}
    return self.data.readb();
}

fn isTransmitEmpty(self: *const Serial) u32 {
    return self.line_status.readb() & 0x20;
}

pub fn writeSerial(self: *const Serial, a: u8) void {
    while (self.isTransmitEmpty() == 0) {}
    self.data.writeb(a);
}

pub fn puts(self: *const Serial, data: []const u8) void {
    for (data) |c| self.writeSerial(c);
}

pub const SerialWriter = Writer(
    *const Serial,
    error{},
    struct {
        pub fn writeFn(serial: *const Serial, string: []const u8) error{}!u32 {
            serial.puts(string);
            return string.len;
        }
    }.writeFn,
);

pub fn writer(self: *const Serial) SerialWriter {
    return SerialWriter{ .context = self };
}
