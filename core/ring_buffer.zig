const std = @import("std");

pub const version = "1.2.0";
pub const version_major = 1;
pub const version_minor = 2;
pub const version_patch = 0;

/// Single-Producer Single-Consumer (SPSC) ring buffer with lock-free synchronization.
///
/// This implementation uses atomic operations for thread-safe coordination between
/// exactly one producer (writer) and one consumer (reader). It's optimized for
/// high-performance, low-latency stream processing like networking I/O.
///
/// **Design:**
/// - Power-of-two size for O(1) wrap-around via bitmask
/// - 64-byte aligned to prevent false sharing between threads
/// - Acquire/Release semantics for thread synchronization without locks
/// - Non-blocking: writer and reader never wait for each other
///
/// **Usage Example:**
/// ```zig
/// var buffer = RingBuffer(4096).init();
/// try buffer.ring_buffer_write("Hello");
/// var out: [256]u8 = undefined;
/// const n = try buffer.ring_buffer_read(&out);
/// ```
///
/// **Thread Safety:**
/// - Safe when called from exactly 2 threads: one writer, one reader
/// - Undefined behavior if multiple threads write or multiple threads read simultaneously
/// - Use Mutex if you need multiple producers or consumers
pub fn RingBuffer(comptime buffer_size: usize) type {
    comptime {
        // Power-of-two ensures bitmask wrap-around works correctly
        if ((buffer_size & (buffer_size - 1)) != 0) {
            @compileError("Buffer is not power of two");
        }
    }

    return struct {
        /// Raw storage for buffered bytes. Contents are uninitialized until written.
        ring_buffer: [buffer_size]u8 align(64) = undefined,
        /// Read head: next byte to be consumed by reader.
        /// Written by reader thread only, read by writer for full/available checks.
        head: std.atomic.Value(usize),
        /// Write tail: next position where writer will place a byte.
        /// Written by writer thread only, read by reader for empty/num_items checks.
        tail: std.atomic.Value(usize),
        /// Bitmask for O(1) wrap-around: (buffer_size - 1).
        /// Equivalent to modulo but faster: `index & mask` instead of `index % size`.
        ring_buffer_bitmask: usize = 0,

        /// Initializes a new ring buffer with all positions at zero.
        pub fn init() RingBuffer(buffer_size) {
            return .{
                .ring_buffer = undefined,
                .ring_buffer_bitmask = buffer_size - 1,
                .head = std.atomic.Value(usize).init(0),
                .tail = std.atomic.Value(usize).init(0),
            };
        }

        /// Returns true if the buffer contains no readable data (head == tail).
        pub inline fn ring_buffer_empty(self: @This()) bool {
            return self.head.load(.acquire) == self.tail.load(.acquire);
        }

        /// Returns true if the buffer is completely full and cannot accept more data.
        /// Full condition: the number of items equals the buffer capacity.
        pub inline fn ring_buffer_full(self: @This()) bool {
            return ((self.tail.load(.acquire) -% self.head.load(.acquire)) & self.ring_buffer_bitmask) == self.ring_buffer_bitmask;
        }

        /// Returns the number of bytes currently stored in the buffer and ready to read.
        pub inline fn ring_buffer_num_items(self: @This()) usize {
            return (self.tail.load(.acquire) -% self.head.load(.acquire)) & self.ring_buffer_bitmask;
        }

        /// Returns the number of bytes that can still be written without overwriting unread data.
        pub inline fn ring_buffer_avaliable(self: @This()) usize {
            return self.ring_buffer_bitmask - self.ring_buffer_num_items();
        }

        /// Writes data into the buffer.
        ///
        /// **Thread Safety:** Call from producer thread only.
        ///
        /// **Errors:**
        /// - `error.NoSpaceLeft`: Not enough contiguous space for all data.
        ///   The buffer is left unchanged; you may retry with fewer bytes.
        pub inline fn ring_buffer_write(self: *@This(), data: []const u8) !void {
            if (data.len > self.ring_buffer_avaliable()) return error.NoSpaceLeft;

            var current_tail = self.tail.load(.acquire);

            for (data) |byte| {
                self.ring_buffer[current_tail] = byte;
                current_tail = (current_tail + @as(usize, 1)) & self.ring_buffer_bitmask;
            }
            // Release semantics ensure all writes are visible to the reader
            self.tail.store(current_tail, .release);
        }

        /// Reads up to `out_data.len` bytes from the buffer into `out_data`.
        ///
        /// **Thread Safety:** Call from consumer thread only.
        ///
        /// **Returns:** Number of bytes actually read (may be less than `out_data.len`
        /// if the buffer doesn't have enough data).
        pub inline fn ring_buffer_read(self: *@This(), out_data: []u8) !usize {
            var r: usize = 0;

            const current_tail: usize = self.tail.load(.acquire);
            var current_head: usize = self.head.load(.acquire);
            while (current_head != current_tail and r < out_data.len) {
                out_data[r] = self.ring_buffer[current_head];
                current_head = (current_head + @as(usize, 1)) & self.ring_buffer_bitmask;
                r += 1;
            }
            // Release semantics ensure the writer sees the new head position
            self.head.store(current_head, .release);
            return r;
        }

        /// Peeks at a byte relative to the read position without consuming it.
        ///
        /// **Parameters:**
        /// - `index`: Offset from current read position (0 = next byte to be read)
        ///
        /// **Returns:** The byte at that position, or null if index is out of bounds.
        ///
        /// **Thread Safety:** Call from consumer thread only. Safe to call multiple times
        /// without modifying the buffer state.
        pub inline fn ring_buffer_peek(self: @This(), index: usize) ?u8 {
            if (index >= self.ring_buffer_num_items()) return null;

            const i: usize = (self.head.load(.acquire) + @as(usize, index)) & self.ring_buffer_bitmask;
            return self.ring_buffer[i];
        }
    };
}
