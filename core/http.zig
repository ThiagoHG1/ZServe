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
    tmp: [1024]u8 = undefined,

    pub fn init(stream: std.net.Stream) BufferedReader {
        return .{
            .buffer = ring_buffer.RingBuffer(4096).init(),
            .stream = stream,
        };
    }

    pub fn fill(self: *BufferedReader) !void {
        const size = 4096;
        const busy = (self.buffer.tail + size - self.buffer.head) % size;
        const available = size - busy - 1;

        if (available == 0) return error.BufferFull;

        var temp: [4096]u8 = undefined;
        const ler = @min(available, temp.len);
        const n = try self.stream.read(temp[0..ler]);
        if (n == 0) return error.EndOfStream;

        try self.buffer.write(temp[0..n]);
    }

    pub fn readExact(self: *BufferedReader, dest: []u8) !void {
        const n = dest.len;
        while (true) {
            const busy = (self.buffer.tail + 4096 - self.buffer.head) % 4096;
            if (busy >= n) break;
            try self.fill();
        }

        _ = try self.buffer.read(dest);
    }

    pub fn readUntil(self: *BufferedReader, delimiter: u8) ![]u8 {
        var out_pos: usize = 0;
        while (true) {
            var byte: [1]u8 = undefined;
            const read = self.buffer.read(&byte) catch 0;

            if (read == 0) {
                try self.fill();
                continue;
            }

            if (byte[0] == delimiter) {
                return self.tmp[0..out_pos];
            }

            if (out_pos >= self.tmp.len) return error.StreamTooLong;
            self.tmp[out_pos] = byte[0];
            out_pos += 1;
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
        try self.buffer.write(bytes);
    }

    pub fn flush(self: *@This()) !void {
        if (self.buffer.head == self.buffer.tail) return;

        const end = if (self.buffer.tail > self.buffer.head) self.buffer.tail else 4096;
        try self.stream.writeAll(self.buffer.buffer[self.buffer.head..end]);

        if (self.buffer.tail < self.buffer.head) {
            try self.stream.writeAll(self.buffer.buffer[0..self.buffer.tail]);
        }

        self.buffer.head = 0;
        self.buffer.tail = 0;
    }
};
