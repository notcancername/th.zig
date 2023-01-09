const std = @import("std");

/// Creates a `BitReader` that reads from `reader`.
pub fn bitReader(reader: anytype) BitReader(usize, @TypeOf(reader)) {
    return .{ .buf = undefined, .bits_left = 0, .reader = reader };
}

/// Reads according to the Theora bit-packing convention. Its first argument is
/// the type that will be used as a "byte". The second argument specifies the
/// type of reader that will be used. Use `bitReader` to create one easily.
pub fn BitReader(comptime Byte: type, comptime Reader: type) type {
    // XXX: optimize
    return struct {
        const Self = @This();
        pub const Error =
            Reader.Error ||
            error{
                EndOfStream,
                Overflow,
                TooLong,
                NotEnoughBytes,
                OutOfMemory
        };
        buf: Byte = 0,
        bits_left: usize = 0,
        reader: Reader,

        pub fn fillBuffer(self: *Self) Error!void {
            const byte_bytes = @divExact(@bitSizeOf(Byte), 8);
            var bytes: [byte_bytes]u8 = undefined;

            const nb_read = try self.reader.readAll(&bytes);
            if (nb_read == 0) return error.EndOfStream;
            self.bits_left = @intCast(@TypeOf(self.bits_left), nb_read * 8);
            self.buf = std.mem.readIntBig(Byte, &bytes);
        }

        inline fn getMsb(self: *Self) u1 {
            return @intCast(u1, self.buf >> (@bitSizeOf(Byte) - 1));
        }

        pub inline fn readBit(self: *Self) Error!u1 {
            if (self.bits_left == 0) try self.fillBuffer();
            self.bits_left -= 1;
            defer self.buf <<= 1;
            return self.getMsb();
        }

        pub inline fn readBool(self: *Self) Error!bool {
            return try self.readBit() != 0;
        }

        pub inline fn readInt(self: *Self, comptime T: type) Error!T {
            switch (@typeInfo(T)) {
                .Int => |int| {
                    var ret: std.meta.Int(.unsigned, int.bits) = 0;
                    comptime var i = 0;
                    inline while (i < int.bits) : (i += 1)
                        ret = (ret << 1) | try self.readBit();
                    return @bitCast(T, ret);
                },
                else => @compileError(""),
            }
        }

        pub inline fn read(self: *Self, ptr: anytype) Error!void {
            if (@typeInfo(@typeInfo(@TypeOf(ptr)).Pointer.child) != .Int)
                @compileError("");
            ptr.* = try self.readInt(@TypeOf(ptr.*));
        }

        pub inline fn readO(self: *Self, comptime T: type, ptr: anytype) Error!void {
            if (@typeInfo(@typeInfo(@TypeOf(ptr)).Pointer.child) != .Int)
                @compileError("");
            const tmp = try self.readInt(T);
            if (tmp > std.math.maxInt(@TypeOf(ptr.*)) or tmp < std.math.minInt(@TypeOf(ptr.*)))
                return error.Overflow;
            ptr.* = @intCast(@TypeOf(ptr.*), tmp);
        }

        pub inline fn readBits(self: *Self, comptime T: type, bits: std.meta.Log2Int(T)) Error!T {
            if (!std.meta.trait.isUnsignedInt(T)) @compileError("");
            var ret: T = 0;

            var i = 0;
            while (i < bits) : (i += 1)
                ret = (ret << 1) | try self.readBit();
            return ret;
        }

        pub inline fn readStringLength(self: *Self) Error!u32 {
            const len0: u32 = try self.readInt(u8);
            const len1: u32 = try self.readInt(u8);
            const len2: u32 = try self.readInt(u8);
            const len3: u32 = try self.readInt(u8);
            return len0 + (len1 << 8) + (len2 << 16) + (len3 << 24);
        }

        pub inline fn readStringAlloc(self: *Self, a: std.mem.Allocator, max: usize) Error![]const u8 {
            const len = try self.readStringLength();
            if(len >= max) return error.TooLong;

            var str = try a.alloc(u8, len);
            errdefer a.free(str);

            // The standard specifies this in terms of bit packing but this should be fine.
            const read_len = try self.reader.readAll(str);
            if(read_len != len) return error.NotEnoughBytes;
            return str;
        }
    };
}

test "BitReader" {
    const inbuf = [_]u8{
        0x80, 0x74, 0x68, 0x65, 0x6f, 0x72, 0x61,
    };
    var outbuf: [inbuf.len]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&inbuf);
    var br = bitReader(fbs.reader());
    outbuf[0] = try br.readInt(u8);
    outbuf[1] = try br.readInt(u8);
    outbuf[2] = try br.readInt(u8);
    outbuf[3] = try br.readInt(u8);
    outbuf[4] = try br.readInt(u8);
    outbuf[5] = try br.readInt(u8);
    outbuf[6] = try br.readInt(u8);
    try std.testing.expectEqual(inbuf, outbuf);
}
