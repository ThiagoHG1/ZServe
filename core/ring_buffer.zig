const std = @import("std");

/// Ring buffer implementation using a power-of-two size and bitmask-based indexing.
/// Designed for high-performance, low-level stream processing (e.g. networking).
pub fn RingBuffer(comptime buffer_size: usize) type {
    comptime {
        // Ensures bitmask wrap-around works correctly
        if ((buffer_size & (buffer_size - 1)) != 0) {
            @compileError("Buffer is not power of two");
        }
    }

    return struct {
        /// Internal storage. Contents are uninitialized on creation.
        ring_buffer: [buffer_size]u8 = undefined,

        /// Read position (next byte to be consumed).
        head: usize = 0,

        /// Write position (next byte to be written).
        tail: usize = 0,

        /// Bitmask used for fast wrap-around (buffer_size - 1).
        ring_buffer_bitmask: usize = 0,

        /// Initializes the ring buffer.
        /// Note: buffer contents are undefined until written.
        pub fn init() RingBuffer(buffer_size) {
            return .{
                .ring_buffer = undefined,
                .ring_buffer_bitmask = buffer_size - 1,
                .head = 0,
                .tail = 0,
            };
        }

        /// Returns true if the buffer contains no readable data.
        pub fn ring_buffer_empty(self: @This()) bool {
            return self.head == self.tail;
        }

        /// Returns true if the buffer is full and cannot accept more data.
        pub fn ring_buffer_full(self: @This()) bool {
            return ((self.head - self.tail) & self.ring_buffer_bitmask) == self.ring_buffer_bitmask;
        }

        /// Returns the number of bytes currently stored in the buffer.
        pub fn ring_buffer_num_items(self: @This()) usize {
            return (self.tail - self.head) & self.ring_buffer_bitmask;
        }

        /// Returns how many bytes can still be written without overwriting unread data.
        pub fn ring_buffer_avaliable(self: @This()) usize {
            return self.ring_buffer_bitmask - self.ring_buffer_num_items();
        }

        /// Writes data into the buffer.
        /// Fails with error.NoSpaceLeft if there is not enough capacity.
        /// Uses bitmask-based wrap-around for constant-time writes.
        pub fn ring_buffer_write(self: *@This(), data: []const u8) !void {
            if (data.len > self.ring_buffer_avaliable()) return error.NoSpaceLeft;

            for (data) |byte| {
                self.ring_buffer[self.tail] = byte;
                self.tail = (self.tail + 1) & self.ring_buffer_bitmask;
            }
        }

        /// Reads up to out_data.len bytes from the buffer.
        /// Returns the number of bytes actually read (may be less if buffer is partially filled).
        /// Advances the read position (head).
        pub fn ring_buffer_read(self: *@This(), out_data: []u8) !usize {
            var r: usize = 0;

            while (self.head != self.tail and r < out_data.len) {
                out_data[r] = self.ring_buffer[self.head];
                self.head = (self.head + 1) & self.ring_buffer_bitmask;
                r += 1;
            }

            return r;
        }

        /// Returns the byte at the given index without advancing the read position.
        /// Index is relative to the current head (read position).
        /// Returns null if the index is out of bounds.
        pub fn ring_buffer_peek(self: @This(), index: usize) ?u8 {
            if (index >= self.ring_buffer_num_items()) return null;

            const i = (self.head + index) & self.ring_buffer_bitmask;
            return self.ring_buffer[i];
        }
    };
}
