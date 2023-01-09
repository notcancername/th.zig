const std = @import("std");
const builtin = @import("builtin");

// Mathematical operations as defined by Theora
pub inline fn mul(a: anytype, b: anytype) !@TypeOf(a, b) {
    const T = @TypeOf(a, b);
    return std.math.mul(T, a, b);
}
pub inline fn add(a: anytype, b: anytype) !@TypeOf(a, b) {
    const T = @TypeOf(a, b);
    return std.math.add(T, a, b);
}
pub inline fn sub(a: anytype, b: anytype) !@TypeOf(a, b) {
    const T = @TypeOf(a, b);
    return std.math.sub(T, a, b);
}
pub inline fn div(a: anytype, b: anytype) !@TypeOf(a, b) {
    const T = @TypeOf(a, b);
    return std.math.divTrunc(T, a, b);
}
pub inline fn ilog(a: anytype) !@TypeOf(a) {
    return if(a < 0) 0 else std.math.log2_int_ceil(@TypeOf(a), a);
}
pub inline fn max(a: anytype, b: anytype) @TypeOf(a, b) {
    return if(a > b) a else b;
}
pub inline fn min(a: anytype, b: anytype) @TypeOf(a, b) {
    return if(a < b) a else b;
}

pub inline fn summation(comptime T: type, start: anytype, end: anytype, step: anytype, array: anytype) !T {
    const x: @TypeOf(start, end, step) = start;
    const sum: T = 0;
    // XXX
    while(x <= end) : (x += step)
        sum = try add(sum, array[x]);
    return sum;
};

pub const AssertLevel = enum(u2) {
    Normal = 0,
    SpeedCritical = 1,
    SanityCheck = 2,
};

pub inline fn assert(comptime level: AssertLevel, cond: bool, err: anytype) !void {
    const enabled = comptime switch(level) {
        .SpeedCritical, .SanityCheck => builtin.mode != .Debug,
        .Normal => builtin.mode != .ReleaseFast,
    };

    if(enabled and !cond) return err;
}

pub inline fn assertPanic(comptime level: AssertLevel, cond: bool) void {
    assert(level, cond, error.Placeholder) catch @panic("Assertion failed");
}
