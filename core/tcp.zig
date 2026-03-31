const std = @import("std");
const http = @import("http.zig");

/// Minimal TCP client with integrated buffered I/O.
/// Wraps a TCP stream and provides higher-level read/write operations
/// using BufferedReader and BufferedWriter.
pub const TcpClient = struct {
    /// Underlying TCP stream.
    stream: std.net.Stream,

    /// Allocator used for network operations.
    allocator: std.mem.Allocator,

    /// Buffered reader for efficient stream consumption.
    reader: http.BufferedReader,

    /// Buffered writer for batched writes.
    writer: http.BufferedWriter,

    /// Establishes a TCP connection to the given host and port.
    /// Initializes internal buffered reader and writer over the stream.
    pub fn connect(allocator: std.mem.Allocator, host: []const u8, port: u16) !TcpClient {
        const stream = try std.net.tcpConnectToHost(allocator, host, port);
        return TcpClient{
            .stream = stream,
            .allocator = allocator,
            .reader = http.BufferedReader.init(stream),
            .writer = http.BufferedWriter.init(stream),
        };
    }

    /// Sends data through the connection.
    /// Data is buffered and then flushed immediately.
    pub fn send(self: *TcpClient, data: []const u8) !void {
        try self.writer.write(data);
        try self.writer.flush();
    }

    /// Closes the underlying TCP stream.
    /// Does not free allocator-owned resources.
    pub fn close(self: *TcpClient) void {
        self.stream.close();
    }
};
