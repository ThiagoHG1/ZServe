const std = @import("std");
const net = std.net;
const http = @import("http.zig");

/// Starts a TCP server bound to the given IP and port.
/// Accepts connections in a blocking loop and handles requests sequentially.
/// Designed as a minimal HTTP server for testing and protocol experimentation.
///
/// Note:
/// - Single-threaded (no concurrency)
/// - No timeout handling
/// - Each connection is fully handled before accepting the next
pub fn OpenServer(allocator: std.mem.Allocator, comptime ip: []const u8, port: u16) !void {
    const addr = try net.Address.parseIp(ip, port);

    // Create a listening socket with address reuse enabled.
    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    // Main accept loop (blocking).
    while (true) {
        // Wait for an incoming connection.
        const conn = try server.accept();
        {
            // Ensure the connection is closed after handling.
            defer conn.stream.close();

            // Initialize buffered reader over the TCP stream.
            var reader = http.BufferedReader.init(conn.stream);

            // Parse incoming HTTP request from the stream.
            // Allocates memory for method and path.
            var req = try http.Request.parse(allocator, &reader);
            defer req.deinit();

            // Log basic request info.
            std.debug.print("[ZServe] {s} {s}\n", .{ req.method, req.path });

            // Send minimal HTTP response.
            try conn.stream.writeAll("HTTP/1.1 200 OK\r\n\r\nOK");
        }
    }
}
