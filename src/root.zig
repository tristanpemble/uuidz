const builtin = @import("builtin");
const std = @import("std");

const Allocator = std.mem.Allocator;
const Random = std.Random;
const Md5 = std.crypto.hash.Md5;
const Sha1 = std.crypto.hash.Sha1;

const native_endian = builtin.target.cpu.arch.endian();
const rand = std.crypto.random;

const StorageInt = if (native_endian == .big) u128 else [16]u8;

const greg_unix_offset = 0x01B21DD213814000;

fn fieldBitOffset(comptime T: type, comptime field_name: []const u8) u16 {
    const fields = std.meta.fields(T);
    comptime var offset = 0;

    if (!@hasField(T, field_name)) {
        @compileError("Field '" ++ field_name ++ "' does not exist in type '" ++ @typeName(T) ++ "'");
    }

    inline for (fields) |field| {
        if (std.mem.eql(u8, field.name, field_name)) {
            return offset;
        }
        offset += @bitSizeOf(field.type);
    }

    unreachable;
}

fn read(comptime T: type, comptime field_name: []const u8, uuid: *const T) @FieldType(T, field_name) {
    const bytes = @as(*const [@sizeOf(T)]u8, @ptrCast(uuid));
    const offset = fieldBitOffset(T, field_name);
    return std.mem.readPackedInt(@FieldType(T, field_name), bytes, offset, .big);
}

fn write(comptime T: type, comptime field_name: []const u8, uuid: *T, value: @FieldType(T, field_name)) void {
    const bytes = @as(*[@sizeOf(T)]u8, @ptrCast(uuid));
    const offset = fieldBitOffset(T, field_name);
    std.mem.writePackedInt(@FieldType(T, field_name), bytes, offset, value, .big);
}

pub const Uuid = packed union {
    v1: V1,
    v2: V2,
    v3: V3,
    v4: V4,
    v5: V5,
    v6: V6,
    v7: V7,
    v8: V8,

    nil: Nil,
    max: Max,

    pub const Nil = packed struct(u128) { bits: u128 = 0x00000000_0000_0000_0000_000000000000 };
    pub const Max = packed struct(u128) { bits: u128 = 0xFFFFFFFF_FFFF_FFFF_FFFF_FFFFFFFFFFFF };

    pub const namespace = struct {
        pub const dns: Uuid = @bitCast(@as(u128, 0x6ba7b810_9dad_11d1_80b4_00c04fd430c8));
        pub const url: Uuid = @bitCast(@as(u128, 0x6ba7b811_9dad_11d1_80b4_00c04fd430c8));
        pub const oid: Uuid = @bitCast(@as(u128, 0x6ba7b812_9dad_11d1_80b4_00c04fd430c8));
        pub const x500: Uuid = @bitCast(@as(u128, 0x6ba7b814_9dad_11d1_80b4_00c04fd430c8));
    };

    // https://www.rfc-editor.org/rfc/rfc9562.html#name-version-field
    pub fn getVersion(self: Uuid) ?Version {
        // Versions are only meaningful and specified on RFC9562 compliant UUIDs.
        if (self.getVariant() != .rfc9562) return null;

        const bytes = @as([16]u8, @bitCast(self));
        const value = std.mem.readPackedInt(u4, &bytes, 76, .big);

        return switch (value) {
            0 => .nil,
            1 => .v1,
            2 => .v2,
            3 => .v3,
            4 => .v4,
            5 => .v5,
            6 => .v6,
            7 => .v7,
            8 => .v8,
            15 => .max,
            else => null,
        };
    }

    // https://www.rfc-editor.org/rfc/rfc9562.html#name-variant-field
    pub fn getVariant(self: Uuid) Variant {
        // This is not as straightforward as you might think. Because variants are stored with
        // variable length encoding, we can't just interpret it as a u4.
        //
        // There is probably a better way to do this, but my brain is fried.

        const bytes = @as([16]u8, @bitCast(self));
        const value = bytes[8];

        if (value & 0b10000000 == 0) return Variant.ncs;
        if (value & 0b11000000 == 0b10000000) return Variant.rfc9562;
        if (value & 0b11100000 == 0b11000000) return Variant.microsoft;

        return Variant.future;
    }

    pub fn getNamespace(self: Uuid) ?Uuid {
        _ = self;
        @panic("todo");
    }

    pub fn getNode(self: Uuid) ?[6]u8 {
        _ = self;
        @panic("todo");
    }

    pub fn getTimestamp(self: Uuid) ?u64 {
        _ = self;
        @panic("todo");
    }

    pub fn isNil(self: Uuid) bool {
        return self == Nil;
    }

    pub fn isMax(self: Uuid) bool {
        return self == Max;
    }

    pub const Version = enum(u4) {
        nil = 0b0000,
        v1 = 1,
        v2 = 2,
        v3 = 3,
        v4 = 4,
        v5 = 5,
        v6 = 6,
        v7 = 7,
        v8 = 8,
        max = 0b1111,

        pub const mac = Version.v1;
        pub const dce = Version.v2;
        pub const md5 = Version.v3;
        pub const random = Version.v4;
        pub const sha1 = Version.v5;
        pub const sort_mac = Version.v6;
        pub const sort_rand = Version.v7;
        pub const custom = Version.v8;
    };

    // Variant is stored with variable length encoding, so cannot be represented as a u2/u4
    pub const Variant = enum {
        ncs,
        rfc9562,
        microsoft,
        future,
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-1
    pub const V1 = packed struct(u128) {
        node: u48,
        clock_seq: u14,
        variant: u2,
        time_high: u12,
        version: u4,
        time_mid: u16,
        time_low: u32,

        pub const Timestamp = struct {
            pub const ns_per_tick = 100;
            pub const ns_unix_offset = greg_unix_offset * ns_per_tick;
            tick: u60,
            seq: u14,
        };

        pub fn init(ts: Timestamp, node: u48) V1 {
            var self: V1 = undefined;

            write(V1, "node", &self, node);
            write(V1, "clock_seq", &self, ts.seq);
            write(V1, "variant", &self, 0b10);
            write(V1, "time_high", &self, @as(u12, @truncate(ts.tick >> 48)));
            write(V1, "version", &self, 1);
            write(V1, "time_mid", &self, @as(u16, @truncate(ts.tick >> 32)));
            write(V1, "time_low", &self, @as(u32, @truncate(ts.tick)));

            return self;
        }

        pub fn getVersion(self: *const V1) Version {
            return (Uuid{ .v1 = self }).getVersion();
        }

        pub fn getVariant(self: *const V1) Variant {
            return (Uuid{ .v1 = self }).getVariant();
        }

        pub fn getTimeLow(self: *const V1) u32 {
            return read(V1, "time_low", self);
        }

        pub fn getTimeMid(self: *const V1) u16 {
            return read(V1, "time_mid", self);
        }

        pub fn getTimeHigh(self: *const V1) u12 {
            return read(V1, "time_high", self);
        }

        pub fn getTime(self: *const V1) u60 {
            const low = self.getTimeLow();
            const mid = self.getTimeMid();
            const high = self.getTimeHigh();
            return (@as(u60, high) << 48) | (@as(u60, mid) << 32) | low;
        }

        pub fn getClockSeq(self: *const V1) u14 {
            return read(V1, "clock_seq", self);
        }

        pub fn getNode(self: *const V1) u48 {
            return read(V1, "node", self);
        }
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-2
    pub const V2 = packed struct(u128) {
        low: u62,
        variant: u2,
        mid: u12,
        version: u4,
        high: u48,

        // Generating a v2 is not (yet) supported.
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-3
    pub const V3 = packed struct(u128) {
        md5_low: u62,
        variant: u2,
        md5_mid: u12,
        version: u4,
        md5_high: u48,

        pub fn init(ns: Uuid, name: []const u8) V3 {
            var hash: [16]u8 = undefined;

            var hasher = Md5.init(.{});
            hasher.update(std.mem.asBytes(&ns));
            hasher.update(name);
            hasher.final(&hash);

            const md5 = std.mem.readInt(u128, &hash, .big);

            var self: V3 = undefined;

            write(V3, "md5_low", &self, @as(u62, @truncate(md5)));
            write(V3, "variant", &self, 0b10);
            write(V3, "md5_mid", &self, @as(u12, @truncate(md5 >> 68)));
            write(V3, "version", &self, 3);
            write(V3, "md5_high", &self, @as(u48, @truncate(md5 >> 80)));

            return self;
        }
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-4
    pub const V4 = packed struct(u128) {
        random_c: u62,
        variant: u2,
        random_b: u12,
        version: u4,
        random_a: u48,

        pub fn init() V4 {
            var self: V4 = undefined;

            write(V4, "random_c", &self, rand.int(u62));
            write(V4, "variant", &self, 0b10);
            write(V4, "random_b", &self, rand.int(u12));
            write(V4, "version", &self, 4);
            write(V4, "random_a", &self, rand.int(u48));

            return self;
        }
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-5
    pub const V5 = packed struct(u128) {
        sha1_low: u62,
        variant: u2,
        sha1_mid: u12,
        version: u4,
        sha1_high: u48,
        pub fn init(ns: Uuid, name: []const u8) V5 {
            var hash: [20]u8 = undefined;

            var hasher = Sha1.init(.{});
            hasher.update(std.mem.asBytes(&ns));
            hasher.update(name);
            hasher.final(&hash);

            const sha1 = std.mem.readInt(u128, hash[0..16], .big);

            var self: V5 = undefined;

            write(V5, "sha1_low", &self, @as(u62, @truncate(sha1)));
            write(V5, "variant", &self, 0b10);
            write(V5, "sha1_mid", &self, @as(u12, @truncate(sha1 >> 68)));
            write(V5, "version", &self, 5);
            write(V5, "sha1_high", &self, @as(u48, @truncate(sha1 >> 80)));

            return self;
        }
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-6
    pub const V6 = packed struct(u128) {
        node: u48,
        clock_seq: u14,
        variant: u2,
        time_low: u12,
        version: u4,
        time_mid: u16,
        time_high: u32,

        pub const Timestamp = struct {
            pub const ns_per_tick = 100;
            pub const ns_unix_offset = greg_unix_offset * ns_per_tick;
            tick: u60,
            seq: u14,
        };
        pub fn init(ts: Timestamp, node: u48) V6 {
            var self: V6 = undefined;

            write(V6, "node", &self, node);
            write(V6, "clock_seq", &self, ts.seq);
            write(V6, "variant", &self, 0b10);
            write(V6, "time_low", &self, @as(u12, @truncate(ts.tick)));
            write(V6, "version", &self, 6);
            write(V6, "time_mid", &self, @as(u16, @truncate(ts.tick >> 12)));
            write(V6, "time_high", &self, @as(u32, @truncate(ts.tick >> 28)));

            return self;
        }
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-7
    pub const V7 = packed struct(u128) {
        rand_b: u62,
        variant: u2,
        rand_a: u12,
        version: u4,
        unix_ts_ms: u48,

        pub const Timestamp = struct {
            pub const ns_per_tick = std.time.ns_per_ms;
            pub const ns_unix_offset = 0;
            tick: u48,
            seq: u74,
        };

        pub fn init(ts: Timestamp) V7 {
            var self: V7 = undefined;

            write(V7, "rand_b", &self, @as(u62, @truncate(ts.seq)));
            write(V7, "variant", &self, 0b10);
            write(V7, "rand_a", &self, @as(u12, @truncate(ts.seq >> 62)));
            write(V7, "version", &self, 7);
            write(V7, "unix_ts_ms", &self, ts.tick);

            return self;
        }
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-8
    pub const V8 = packed struct(u128) {
        custom_c: u62,
        variant: u2,
        custom_b: u12,
        version: u4,
        custom_a: u48,

        pub fn init(custom: u122) V8 {
            var self: V8 = undefined;

            write(V8, "custom_c", &self, @as(u62, @truncate(custom)));
            write(V8, "variant", &self, 0b10);
            write(V8, "custom_b", &self, @as(u12, @truncate(custom >> 62)));
            write(V8, "version", &self, 8);
            write(V8, "custom_a", &self, @as(u48, @truncate(custom >> 74)));

            return self;
        }
    };

    pub fn format(
        self: Uuid,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const bytes = @as([16]u8, @bitCast(self));
        try writer.print("{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8],  bytes[9],  bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15],
        });
    }
};

pub const Clock = struct {
    ptr: *anyopaque,
    nanoTimestampFn: *const fn (ptr: *anyopaque) i128,

    pub const System = Clock.init(&.{}, systemClock);
    pub const Zero = Clock.init(&.{}, zeroClock);

    pub fn init(ptr: *anyopaque, nanoTimestampFn: *const fn (ptr: *anyopaque) i128) Clock {
        return Clock{
            .ptr = ptr,
            .nanoTimestampFn = nanoTimestampFn,
        };
    }

    pub fn nanoTimestamp(self: *const Clock) i128 {
        return self.nanoTimestampFn(self.ptr);
    }

    fn systemClock(_: *anyopaque) i128 {
        return std.time.nanoTimestamp();
    }

    fn zeroClock(_: *anyopaque) i128 {
        return 0;
    }
};

pub fn ClockSequence(comptime Timestamp: type) type {
    return struct {
        pub const Tick = @FieldType(Timestamp, "tick");
        pub const Seq = @FieldType(Timestamp, "seq");

        clock: Clock = Clock.System,
        rand: Random = std.crypto.random,
        last: Tick = 0,
        seq: Seq = 0,

        pub fn next(self: *@This()) Timestamp {
            const tick = self.tickTimestamp();

            if (tick > self.last) {
                self.last = tick;
                self.seq = self.rand.int(Seq);
            } else {
                self.seq +%= 1;
            }

            return .{
                .tick = self.last,
                .seq = self.seq,
            };
        }

        fn tickTimestamp(self: *@This()) Tick {
            const ns = self.clock.nanoTimestamp() + Timestamp.ns_unix_offset;
            return @intCast(@divFloor(ns, Timestamp.ns_per_tick));
        }
    };
}

test "v1 generation" {
    var v1_ctx = ClockSequence(Uuid.V1.Timestamp){};
    const v1 = Uuid{ .v1 = .init(v1_ctx.next(), 69420) };
    std.debug.print("v1 UUID: {}\n", .{v1});
    try std.testing.expect(v1.getVersion() == .v1);
    try std.testing.expect(v1.getVariant() == .rfc9562);
}

test "v3 generation" {
    const v3 = Uuid{ .v3 = .init(Uuid.namespace.dns, "example.com") };
    std.debug.print("v3 UUID: {}\n", .{v3});
    try std.testing.expect(v3.getVersion() == .v3);
    try std.testing.expect(v3.getVariant() == .rfc9562);
}

test "v4 generation" {
    const v4 = Uuid{ .v4 = .init() };
    std.debug.print("v4 UUID: {}\n", .{v4});
    try std.testing.expect(v4.getVersion() == .v4);
    try std.testing.expect(v4.getVariant() == .rfc9562);
}

test "v5 generation" {
    const v5 = Uuid{ .v5 = .init(Uuid.namespace.dns, "example.com") };
    std.debug.print("v5 UUID: {}\n", .{v5});
    try std.testing.expect(v5.getVersion() == .v5);
    try std.testing.expect(v5.getVariant() == .rfc9562);
}

test "v6 generation" {
    var v6_ctx = ClockSequence(Uuid.V6.Timestamp){};
    const v6 = Uuid{ .v6 = .init(v6_ctx.next(), 0x001122334455) };
    std.debug.print("v6 UUID: {}\n", .{v6});
    try std.testing.expect(v6.getVersion() == .v6);
    try std.testing.expect(v6.getVariant() == .rfc9562);
}

test "v7 generation" {
    var v7_ctx = ClockSequence(Uuid.V7.Timestamp){};
    const v7 = Uuid{ .v7 = .init(v7_ctx.next()) };
    std.debug.print("v7 UUID: {}\n", .{v7});
    try std.testing.expect(v7.getVersion() == .v7);
    try std.testing.expect(v7.getVariant() == .rfc9562);
}

test "v8 generation" {
    const v8 = Uuid{ .v8 = .init(0x123456789ABCDEF0123456789ABCDE) };
    std.debug.print("v8 UUID: {}\n", .{v8});
    try std.testing.expect(v8.getVersion() == .v8);
    try std.testing.expect(v8.getVariant() == .rfc9562);
}
