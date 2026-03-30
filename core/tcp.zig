const std = @import("std");
const http = @import("http.zig");

pub const TcpClient = struct {
    stream: std.net.Stream,
    allocator: std.mem.Allocator,
    reader: http.BufferedReader,
    writer: http.BufferedWriter,

    pub fn connect(allocator: std.mem.Allocator, host: []const u8, port: u16) !TcpClient {
        const stream = try std.net.tcpConnectToHost(allocator, host, port);
        return TcpClient{
            .stream = stream,
            .allocator = allocator,
            .reader = http.BufferedReader.init(stream),
            .writer = http.BufferedWriter.init(stream),
        };
    }

    pub fn send(self: *TcpClient, data: []const u8) !void {
        try self.writer.write(data);
        try self.writer.flush();
    }

    pub fn close(self: *TcpClient) void {
        self.stream.close();
    }
};
