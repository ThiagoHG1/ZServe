const std = @import("std");
const net = std.net;

pub const NetReader = struct {
    stream: net.Stream,
    buffer: []u8,
    pos: usize = 0,
    len: usize = 0,

    pub fn init(stream: net.Stream, buffer: []u8) NetReader {
        return .{
            .stream = stream,
            .buffer = buffer,
        };
    }

    pub fn read(self: *NetReader, dest: []u8) !usize {
        if (self.pos >= self.len) {
            self.len = try self.stream.read(self.buffer);
            self.pos = 0;
            if (self.len == 0) return 0;
        }
        const avaliable = self.len - self.pos;
        const n = @min(dest.len, avaliable);
        @memcpy(dest[0..n], self.buffer[self.pos .. self.pos + n]);
        self.pos += n;
        return n;
    }

    pub fn any(self: *NetReader) std.io.AnyReader {
        return .{
            .context = self,
            .readFn = struct {
                fn read(context: *const anyopaque, buffer: []u8) anyerror!usize {
                        const ptr: *NetReader = @ptrCast(@constCast(@alignCast(context)));
                    return ptr.read(buffer);
                }
            }.read,
        };
    }
};

pub const Request = struct {
    method: []const u8,
    path: []const u8,
    reader: std.io.AnyReader,
    allocator: std.mem.Allocator,

    pub fn parse(allocator: std.mem.Allocator, reader: std.io.AnyReader) !Request {
        var line_buff: [1024]u8 = undefined;
        const line = (try reader.readUntilDelimiterOrEof(&line_buff, '\n')) orelse return error.EmptyRequest;

        const clean_line = std.mem.trim(u8, line, " \r\t");
        var it = std.mem.tokenizeSequence(u8, clean_line, " ");
        const method_raw = it.next() orelse return error.InvalidMethod;
        const path_raw = it.next() orelse return error.InvalidPath;

        return Request {
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
