const std = @import("std");
const net = std.net;
const http = @import("http.zig");

pub fn OpenServer(allocator: std.mem.Allocator, comptime ip: []const u8, port: u16) !void {
    const addr = try net.Address.parseIp(ip, port);

    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    while (true) {
        const conn = try server.accept();
        {
            defer conn.stream.close();
            var reader = http.BufferedReader.init(conn.stream);
            var req = try http.Request.parse(allocator, &reader);
            defer req.deinit();
            std.debug.print("[ZServe] {s} {s}\n", .{ req.method, req.path });
            try conn.stream.writeAll("HTTP/1.1 200 OK\r\n\r\nOK");
        }
    }
}
