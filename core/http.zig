const std = @import("std");
const ring_buffer = @import("ring_buffer.zig");
const net = std.net;

/// Represents a minimal HTTP request.
/// Only parses the request line (method + path).
pub const Request = struct {
    /// HTTP method (e.g., "GET", "POST").
    method: []const u8,

    /// Request path (e.g., "/", "/api/users").
    path: []const u8,

    /// Reference to the buffered reader used for parsing.
    /// Allows further reads (headers/body) after parsing.
    reader: *BufferedReader,

    /// Allocator used for duplicating parsed data.
    allocator: std.mem.Allocator,

    /// Parses the HTTP request line from the stream.
    ///
    /// Expected format:
    ///   METHOD PATH HTTP/VERSION
    ///
    /// Example:
    ///   GET /index.html HTTP/1.1
    ///
    /// Only method and path are extracted.
    /// Allocates memory for both fields.
    pub fn parse(allocator: std.mem.Allocator, reader: *BufferedReader) !Request {
        // Read a single line (request line)
        const line = try reader.readUntil(allocator, '\n');

        // Trim whitespace and CRLF artifacts
        const clean_line = std.mem.trim(u8, line, " \r\t");

        // Split by space: METHOD PATH HTTP/VERSION

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

    /// Frees allocated memory for method and path.
    /// Must be called after usage to avoid leaks.
    pub fn deinit(self: *Request) void {
        self.allocator.free(self.method);
        self.allocator.free(self.path);
    }
};

/// Buffered reader built on top of a ring buffer.
/// Minimizes syscalls by batching reads from the TCP stream.
pub const BufferedReader = struct {
    /// Internal circular buffer used to store incoming data.
    buffer: ring_buffer.RingBuffer(4096),

    /// Underlying TCP stream.
    stream: std.net.Stream,

    /// Initializes the buffered reader with a given stream.
    /// Starts with an empty buffer.
    pub fn init(stream: std.net.Stream) BufferedReader {
        return .{
            .buffer = ring_buffer.RingBuffer(4096).init(),
            .stream = stream,
        };
    }

    /// Fills the internal buffer with data from the stream.
    ///
    /// Reads up to the available space in the ring buffer.
    /// Returns:
    /// - error.BufferFull if no space is available
    /// - error.EndOfStream if the connection is closed
    pub fn fill(self: *BufferedReader) !void {
        if (self.buffer.ring_buffer_full()) return error.BufferFull;

        var temp: [4096]u8 = undefined;

        // Limit read size to available space in buffer
        const ler = @min(self.buffer.ring_buffer_avaliable(), temp.len);
        const n = try self.stream.read(temp[0..ler]);
        if (n == 0) return error.EndOfStream;

        try self.buffer.ring_buffer_write(temp[0..n]);
    }

    /// Attempts to read exactly `dest.len` bytes into `dest`.
    ///
    /// Keeps filling the buffer until data is available.
    /// Behavior depends on internal buffer state.
    pub fn readExact(self: *BufferedReader, dest: []u8) !void {
        const n = dest.len;
        while (true) {
            // Wait until buffer has enough data
            if (try self.buffer.ring_buffer_full() >= n) break;
            try self.fill();
        }

        _ = try self.buffer.ring_buffer_read(dest);
    }

    /// Reads bytes until a delimiter is found.
    ///
    /// Returns a newly allocated slice containing all bytes read
    /// (excluding the delimiter).
    ///
    /// Keeps consuming from the buffer and refilling as needed.
    pub fn readUntil(self: *BufferedReader, allocator: std.mem.Allocator, delimiter: u8) ![]u8 {
        var temp: std.ArrayList(u8) = .empty;
        errdefer temp.deinit(allocator);

        while (true) {
            var byte: [1]u8 = undefined;

            // Try to read a single byte from buffer
            const read = self.buffer.ring_buffer_read(&byte) catch 0;

            if (read == 0) {
                try self.fill();
                continue;
            }

            // Stop when delimiter is found
            if (byte[0] == delimiter) {
                return try temp.toOwnedSlice(allocator);
            }

            try temp.append(allocator, byte[0]);
        }
    }
};

/// Buffered writer built on top of a ring buffer.
/// Batches writes to reduce syscall overhead.
pub const BufferedWriter = struct {
    /// Internal circular buffer storing outgoing data.
    buffer: ring_buffer.RingBuffer(4096),

    /// Underlying TCP stream.
    stream: std.net.Stream,

    /// Initializes the buffered writer with a given stream.
    /// Starts with an empty buffer.
    pub fn init(stream: std.net.Stream) @This() {
        return .{
            .buffer = ring_buffer.RingBuffer(4096).init(),
            .stream = stream,
        };
    }

    /// Writes data into the internal buffer.
    ///
    /// Does not send data immediately.
    /// Returns error if there is not enough space in the buffer.
    pub fn write(self: *@This(), bytes: []const u8) !void {
        try self.buffer.ring_buffer_write(bytes);
    }

    /// Flushes buffered data to the stream.
    ///
    /// Handles wrap-around in the ring buffer by performing
    /// up to two writes:
    /// - from head to end
    /// - from start to tail (if wrapped)
    ///
    /// Resets buffer indices after successful write.
    pub fn flush(self: *@This()) !void {
        if (self.buffer.ring_buffer_empty()) return;

        // Determine contiguous region from head
        const end = if (self.buffer.tail > self.buffer.head)
            self.buffer.tail
        else
            self.buffer.ring_buffer.len;

        // Write first segment
        try self.stream.writeAll(self.buffer.ring_buffer[self.buffer.head..end]);

        // If wrapped, write remaining segment
        if (self.buffer.tail < self.buffer.head) {
            try self.stream.writeAll(self.buffer.ring_buffer[0..self.buffer.tail]);
        }

        // Reset buffer state
        self.buffer.head = 0;
        self.buffer.tail = 0;
    }
};
