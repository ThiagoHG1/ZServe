const std = @import("std");

pub fn RingBuffer(comptime buffer_size: usize) type {
    comptime {
        if ((buffer_size & (buffer_size - 1)) != 0) {
            @compileError("Buffer is not power of two");
        }
    }

    return struct {
        ring_buffer: [buffer_size]u8 = undefined,
        head: usize = 0,
        tail: usize = 0,
        ring_buffer_bitmask: usize = 0,

        pub fn init() RingBuffer(buffer_size) {
            return .{
                .ring_buffer = undefined,
                .ring_buffer_bitmask = buffer_size - 1,
                .head = 0,
                .tail = 0,
            };
        }

        pub fn ring_buffer_empty(self: @This()) bool {
            return self.head == self.tail;
        }

        pub fn ring_buffer_full(self: @This()) bool {
            return ((self.head - self.tail) & self.ring_buffer_bitmask) == self.ring_buffer_bitmask;
        }

        pub fn ring_buffer_num_items(self: @This()) usize {
            return (self.tail - self.head) & self.ring_buffer_bitmask;
        }

        pub fn ring_buffer_avaliable(self: @This()) usize {
            return self.ring_buffer_bitmask - self.ring_buffer_num_items();
        }

        pub fn ring_buffer_write(self: *@This(), data: []const u8) !void {
            if (data.len > self.ring_buffer_avaliable()) return error.NoSpaceLeft;

            for (data) |byte| {
                self.ring_buffer[self.tail] = byte;
                self.tail = (self.tail + 1) & self.ring_buffer_bitmask;
            }
        }

        pub fn ring_buffer_read(self: *@This(), out_data: []u8) !usize {
            var r: usize = 0;

            while (self.head != self.tail and r < out_data.len) {
                out_data[r] = self.ring_buffer[self.head];
                self.head = (self.head + 1) & self.ring_buffer_bitmask;
                r += 1;
            }

            return r;
        }

        pub fn ring_buffer_peek(self: @This(), index: usize) ?u8 {
            if (index >= self.ring_buffer_num_items()) return null;

            const i = (self.head + index) & self.ring_buffer_bitmask;
            return self.ring_buffer[i];
        }
    };
}
