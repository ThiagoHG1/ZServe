const std = @import("std");

/// Internal buffer used for stdout writes.
/// Large buffer reduces syscall frequency significantly.
var stdout_buffer: [65536]u8 = undefined;

/// Buffered writer bound to stdout using the internal buffer.
var stdout_file_writer = std.fs.File.stdout().writer(&stdout_buffer);

/// Writer interface used for formatted output.
const stdout = &stdout_file_writer.interface;

/// Writes formatted text to stdout using a buffered writer.
///
/// Does not flush automatically.
/// Call `flush()` to ensure data is written to the OS.
pub fn print(comptime fmt: []const u8, args: anytype) !void {
    try stdout.print(fmt, args);
}

/// Flushes the internal buffer to stdout.
///
/// Must be called to guarantee all buffered data is written.
pub fn flush() !void {
    try stdout.flush();
}
