const std = @import("std");

pub fn RingBuffer(comptime size: usize) type {
    return struct {
        buffer: [size]u8 = undefined,
        head: usize = 0,
        tail: usize = 0,

        pub fn init() @This() {
            return .{
                .head = 0,
                .tail = 0,
            };
        }

        pub fn write(self: *@This(), data: []const u8) !void {
            const busy = (self.tail + size - self.head) % size;
            const avaliable = size - busy - 1;

            if (data.len > avaliable) return error.NoSpaceLeft;

            for (data) |byte| {
                self.buffer[self.tail] = byte;
                self.tail = (self.tail + 1) % size;
            }
        }

        pub fn read(self: *@This(), out_data: []u8) !usize {
            var r: usize = 0;

            while (self.head != self.tail and r < out_data.len) {
                out_data[r] = self.buffer[self.head];
                self.head = (self.head + 1) % size;
                r += 1;
            }

            return r;
        }
    };
}
