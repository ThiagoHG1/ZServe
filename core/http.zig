const std = @import("std");
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
    buffer: [4096]u8 = undefined,
    pos: usize,
    len: usize,
    stream: std.net.Stream,

    pub fn init(stream: std.net.Stream) BufferedReader {
        return .{
            .stream = stream,
            .pos = 0,
            .len = 0,
        };
    }

    pub fn fill(self: *BufferedReader) !void {
        if (self.buffer[self.len..4096].len == 0) {
            const rest = self.len - self.pos;
            if (rest == 4096) {
                return error.BufferFull;
            }

            std.mem.copyForwards(u8, self.buffer[0..rest], self.buffer[self.pos..self.len]);
            self.pos = 0;
            self.len = rest;
        }

        var buf: [4096]u8 = undefined;
        var r = self.stream.reader(&buf);
        const n = try r.interface().readSliceShort(self.buffer[self.len..]);
        self.len += n;
    }

    pub fn readExact(self: *@This(), n: usize) ![]u8 {
        while (self.len - self.pos < n) {
            try self.fill();
        }

        const result = self.buffer[self.pos .. self.pos + n];
        self.pos += n;
        return result;
    }

    pub fn readUntil(self: *@This(), delimiter: u8) ![]u8 {
        while (true) {
            if (std.mem.indexOfScalar(u8, self.buffer[self.pos..self.len], delimiter)) |index| {
                const start = self.pos;
                const end = self.pos + index;

                self.pos = end + 1;

                return self.buffer[start..end];
            }

            try self.fill();
        }
    }
};

pub const BufferedWriter = struct {
    buffer: [4096]u8 = undefined,
    len: usize,
    stream: std.net.Stream,

    pub fn init(stream: std.net.Stream) @This() {
        return .{
            .len = 0,
            .stream = stream,
        };
    }

    pub fn write(self: *@This(), bytes: []const u8) !void {
        if (self.len + bytes.len > self.buffer.len) {
            try self.flush();
        }

        std.mem.copyForwards(u8, self.buffer[self.len .. self.len + bytes.len], bytes);
        self.len += bytes.len;
    }

    pub fn flush(self: *@This()) !void {
        try self.stream.writeAll(self.buffer[0..self.len]);
        self.len = 0;
    }
};
