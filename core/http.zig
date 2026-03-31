const std = @import("std");
const ring_buffer = @import("ring_buffer.zig");
const net = std.net;

pub const Request = struct {
    method: []const u8,
    path: []const u8,
    reader: *BufferedReader,
    allocator: std.mem.Allocator,

    pub fn parse(allocator: std.mem.Allocator, reader: *BufferedReader) !Request {
        const line = try reader.readUntil('\n');
        const clean_line = std.mem.trim(u8, line, " \r\t");
        var it = std.mem.tokenizeSequence(u8, clean_line, " ");
        const method_raw = it.next() orelse return error.InvalidMethod;
        const path_raw = it.next() orelse return error.InvalidPath;

        return Request{
            .method = try allocator.dupe(u8, method_raw),
            .path = try allocator.dupe(u8, path_raw),
            .reader = reader,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Request) void {
        self.allocator.free(self.method);
        self.allocator.free(self.path);
    }
};

pub const BufferedReader = struct {
    buffer: ring_buffer.RingBuffer(4096),
    stream: std.net.Stream,

    pub fn init(stream: std.net.Stream) BufferedReader {
        return .{
            .buffer = ring_buffer.RingBuffer(4096).init(),
            .stream = stream,
        };
    }

    pub fn fill(self: *BufferedReader) !void {
        if (self.buffer.ring_buffer_full()) return error.BufferFull;

        var temp: [4096]u8 = undefined;
        const ler = @min(self.buffer.ring_buffer_avaliable(), temp.len);
        const n = try self.stream.read(temp[0..ler]);
        if (n == 0) return error.EndOfStream;

        try self.buffer.ring_buffer_write(temp[0..n]);
    }

    pub fn readExact(self: *BufferedReader, dest: []u8) !void {
        const n = dest.len;
        while (true) {
            if (try self.buffer.ring_buffer_full() >= n) break;
            try self.fill();
        }

        _ = try self.buffer.ring_buffer_read(dest);
    }

    pub fn readUntil(self: *BufferedReader, allocator: std.mem.Allocator, delimiter: u8) ![]u8 {
        var temp: std.ArrayList(u8) = .empty;
        errdefer temp.deinit(allocator);

        while (true) {
            var byte: [1]u8 = undefined;
            const read = self.buffer.ring_buffer_read(&byte) catch 0;

            if (read == 0) {
                try self.fill();
                continue;
            }

            if (byte[0] == delimiter) {
                return try temp.toOwnedSlice(allocator);
            }

            try temp.append(allocator, byte[0]);
        }
    }
};

pub const BufferedWriter = struct {
    buffer: ring_buffer.RingBuffer(4096),
    stream: std.net.Stream,

    pub fn init(stream: std.net.Stream) @This() {
        return .{
            .buffer = ring_buffer.RingBuffer(4096).init(),
            .stream = stream,
        };
    }

    pub fn write(self: *@This(), bytes: []const u8) !void {
        try self.buffer.ring_buffer_write(bytes);
    }

    pub fn flush(self: *@This()) !void {
        if (self.buffer.ring_buffer_empty()) return;

        const end = if (self.buffer.tail > self.buffer.head)
            self.buffer.tail
        else
            self.buffer.ring_buffer.len;

        try self.stream.writeAll(self.buffer.ring_buffer[self.buffer.head..end]);

        if (self.buffer.tail < self.buffer.head) {
            try self.stream.writeAll(self.buffer.ring_buffer[0..self.buffer.tail]);
        }

        self.buffer.head = 0;
        self.buffer.tail = 0;
    }
};
