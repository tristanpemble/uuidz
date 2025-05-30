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

fn readField(comptime T: type, comptime field_name: []const u8, uuid: *const T) @FieldType(T, field_name) {
    const bytes = @as(*const [@sizeOf(T)]u8, @ptrCast(uuid));
    const offset = fieldBitOffset(T, field_name);
    return std.mem.readPackedInt(@FieldType(T, field_name), bytes, offset, .big);
}

fn writeField(comptime T: type, comptime field_name: []const u8, uuid: *T, value: @FieldType(T, field_name)) void {
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

    nil: enum(u128) { nil = std.math.minInt(u128) },
    max: enum(u128) { max = std.math.maxInt(u128) },

    pub const Nil: Uuid = .fromNative(0x00000000_0000_0000_0000_000000000000);
    pub const Max: Uuid = .fromNative(0xffffffff_ffff_ffff_ffff_ffffffffffff);

    pub const namespace = struct {
        pub const dns: Uuid = .fromNative(0x6ba7b810_9dad_11d1_80b4_00c04fd430c8);
        pub const url: Uuid = .fromNative(0x6ba7b811_9dad_11d1_80b4_00c04fd430c8);
        pub const oid: Uuid = .fromNative(0x6ba7b812_9dad_11d1_80b4_00c04fd430c8);
        pub const x500: Uuid = .fromNative(0x6ba7b814_9dad_11d1_80b4_00c04fd430c8);
    };

    pub fn fromBytes(bytes: [16]u8) Uuid {
        return @bitCast(bytes);
    }

    pub fn fromNative(int: u128) Uuid {
        return switch (native_endian) {
            .big => fromBig(int),
            .little => fromLittle(int),
        };
    }

    pub fn fromBig(int: u128) Uuid {
        return @bitCast(@as(u128, @intCast(int)));
    }

    pub fn fromLittle(int: u128) Uuid {
        return @bitCast(@byteSwap(@as(u128, @intCast(int))));
    }

    pub fn toBytes(self: Uuid) [16]u8 {
        return @bitCast(self);
    }

    pub fn toNative(self: Uuid) u128 {
        return switch (native_endian) {
            .little => self.toLittle(),
            .big => self.toBig(),
        };
    }

    pub fn toBig(self: Uuid) u128 {
        return @bitCast(self);
    }

    pub fn toLittle(self: Uuid) u128 {
        return @byteSwap(@as(u128, @bitCast(self)));
    }

    pub fn asBytes(self: *const Uuid) *const [16]u8 {
        return @ptrCast(self);
    }

    pub fn asSlice(self: *const Uuid) []const u8 {
        return self.asBytes();
    }

    pub fn eql(self: Uuid, other: Uuid) bool {
        return std.mem.eql(u8, self.asSlice(), other.asSlice());
    }

    pub fn order(self: Uuid, other: Uuid) std.math.Order {
        return std.mem.order(u8, self.asSlice(), other.asSlice());
    }

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

    pub fn isNil(self: Uuid) bool {
        return self.eql(Nil);
    }

    pub fn isMax(self: Uuid) bool {
        return self.eql(Max);
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

            pub fn now() Timestamp {
                return ClockSequence(Timestamp).System.next();
            }
        };

        pub fn init(ts: Timestamp, node: u48) V1 {
            var self: V1 = undefined;

            writeField(V1, "node", &self, node);
            writeField(V1, "clock_seq", &self, ts.seq);
            writeField(V1, "variant", &self, 0b10);
            writeField(V1, "time_high", &self, @as(u12, @truncate(ts.tick >> 48)));
            writeField(V1, "version", &self, 1);
            writeField(V1, "time_mid", &self, @as(u16, @truncate(ts.tick >> 32)));
            writeField(V1, "time_low", &self, @as(u32, @truncate(ts.tick)));

            return self;
        }

        pub fn now(node: u48) V1 {
            return .init(.now(), node);
        }

        pub fn toUuid(self: V1) Uuid {
            return .{ .v1 = self };
        }

        pub fn toBytes(self: V1) [16]u8 {
            return @bitCast(self);
        }

        pub fn toNative(self: V1) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        pub fn toBig(self: V1) u128 {
            return @bitCast(self);
        }

        pub fn toLittle(self: V1) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        pub fn asBytes(self: *const V1) *const [16]u8 {
            return @ptrCast(self);
        }

        pub fn asSlice(self: V1) []u8 {
            return self.asBytes();
        }

        pub fn eql(self: V1, other: V1) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        pub fn order(self: V1, other: V1) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        pub fn getNode(self: V1) u48 {
            return self.getNative("node");
        }

        pub fn getClockSeq(self: V1) u14 {
            return self.getNative("clock_seq");
        }

        pub fn getVariant(self: V1) Variant {
            return self.toUuid().getVariant();
        }

        pub fn getVersion(self: V1) Version {
            return self.toUuid().getVersion().?;
        }

        pub fn getTime(self: V1) u60 {
            const low = self.getNative("time_low");
            const mid = self.getNative("time_mid");
            const high = self.getNative("time_high");

            return (@as(u60, high) << 48) | (@as(u60, mid) << 32) | low;
        }

        pub fn format(
            self: V1,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            return self.toUuid().format(fmt, options, writer);
        }

        fn getNative(self: V1, comptime field_name: []const u8) @FieldType(V1, field_name) {
            return readField(V1, field_name, &self);
        }
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-2
    pub const V2 = packed struct(u128) {
        low: u62,
        variant: u2,
        mid: u12,
        version: u4,
        high: u48,

        pub fn toUuid(self: V2) Uuid {
            return .{ .v2 = self };
        }

        pub fn toBytes(self: V2) [16]u8 {
            return @bitCast(self);
        }

        pub fn toNative(self: V2) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        pub fn toBig(self: V2) u128 {
            return @bitCast(self);
        }

        pub fn toLittle(self: V2) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        pub fn asBytes(self: *const V2) *const [16]u8 {
            return @ptrCast(self);
        }

        pub fn asSlice(self: V2) []u8 {
            return self.asBytes();
        }

        pub fn eql(self: V2, other: V2) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        pub fn order(self: V2, other: V2) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        pub fn getVariant(self: V2) Variant {
            return self.toUuid().getVariant();
        }

        pub fn getVersion(self: V2) Version {
            return self.toUuid().getVersion().?;
        }

        pub fn getLow(self: V2) u62 {
            return self.getNative("low");
        }

        pub fn getMid(self: V2) u12 {
            return self.getNative("mid");
        }

        pub fn getHigh(self: V2) u48 {
            return self.getNative("high");
        }

        pub fn format(
            self: V2,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            return self.toUuid().format(fmt, options, writer);
        }

        fn getNative(self: V2, comptime field_name: []const u8) @FieldType(V2, field_name) {
            return readField(V2, field_name, self);
        }
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

            writeField(V3, "md5_low", &self, @as(u62, @truncate(md5)));
            writeField(V3, "variant", &self, 0b10);
            writeField(V3, "md5_mid", &self, @as(u12, @truncate(md5 >> 68)));
            writeField(V3, "version", &self, 3);
            writeField(V3, "md5_high", &self, @as(u48, @truncate(md5 >> 80)));

            return self;
        }

        pub fn toUuid(self: V3) Uuid {
            return .{ .v3 = self };
        }

        pub fn toBytes(self: V3) [16]u8 {
            return @bitCast(self);
        }

        pub fn toNative(self: V3) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        pub fn toBig(self: V3) u128 {
            return @bitCast(self);
        }

        pub fn toLittle(self: V3) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        pub fn asBytes(self: *const V3) *const [16]u8 {
            return @ptrCast(self);
        }

        pub fn asSlice(self: V3) []u8 {
            return self.asBytes();
        }

        pub fn eql(self: V3, other: V3) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        pub fn order(self: V3, other: V3) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        pub fn getVariant(self: V3) Variant {
            return self.toUuid().getVariant();
        }

        pub fn getVersion(self: V3) Version {
            return self.toUuid().getVersion().?;
        }

        pub fn getMd5(self: V3) u122 {
            const low = self.getNative("md5_low");
            const mid = self.getNative("md5_mid");
            const high = self.getNative("md5_high");

            return (@as(u122, high) << 74) | (@as(u122, mid) << 62) | low;
        }

        pub fn format(
            self: V3,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            return self.toUuid().format(fmt, options, writer);
        }

        fn getNative(self: V3, comptime field_name: []const u8) @FieldType(V3, field_name) {
            return readField(V3, field_name, &self);
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

            writeField(V4, "random_c", &self, rand.int(u62));
            writeField(V4, "variant", &self, 0b10);
            writeField(V4, "random_b", &self, rand.int(u12));
            writeField(V4, "version", &self, 4);
            writeField(V4, "random_a", &self, rand.int(u48));

            return self;
        }

        pub fn toUuid(self: V4) Uuid {
            return .{ .v4 = self };
        }

        pub fn toBytes(self: V4) [16]u8 {
            return @bitCast(self);
        }

        pub fn toNative(self: V4) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        pub fn toBig(self: V4) u128 {
            return @bitCast(self);
        }

        pub fn toLittle(self: V4) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        pub fn asBytes(self: *const V4) *const [16]u8 {
            return @ptrCast(self);
        }

        pub fn asSlice(self: V4) []u8 {
            return self.asBytes();
        }

        pub fn eql(self: V4, other: V4) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        pub fn order(self: V4, other: V4) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        pub fn getVariant(self: V4) Variant {
            return self.toUuid().getVariant();
        }

        pub fn getVersion(self: V4) Version {
            return self.toUuid().getVersion().?;
        }

        pub fn getRandom(self: V4) u122 {
            const c = self.getNative("random_c");
            const b = self.getNative("random_b");
            const a = self.getNative("random_a");

            return (@as(u122, a) << 74) | (@as(u122, b) << 62) | c;
        }

        pub fn format(
            self: V4,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            return self.toUuid().format(fmt, options, writer);
        }

        fn getNative(self: V4, comptime field_name: []const u8) @FieldType(V4, field_name) {
            return readField(V4, field_name, &self);
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

            writeField(V5, "sha1_low", &self, @as(u62, @truncate(sha1)));
            writeField(V5, "variant", &self, 0b10);
            writeField(V5, "sha1_mid", &self, @as(u12, @truncate(sha1 >> 68)));
            writeField(V5, "version", &self, 5);
            writeField(V5, "sha1_high", &self, @as(u48, @truncate(sha1 >> 80)));

            return self;
        }

        pub fn toUuid(self: V5) Uuid {
            return .{ .v5 = self };
        }

        pub fn toBytes(self: V5) [16]u8 {
            return @bitCast(self);
        }

        pub fn toNative(self: V5) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        pub fn toBig(self: V5) u128 {
            return @bitCast(self);
        }

        pub fn toLittle(self: V5) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        pub fn asBytes(self: *const V5) *const [16]u8 {
            return @ptrCast(self);
        }

        pub fn asSlice(self: V5) []u8 {
            return self.asBytes();
        }

        pub fn eql(self: V5, other: V5) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        pub fn order(self: V5, other: V5) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        pub fn getVariant(self: V5) Variant {
            return self.toUuid().getVariant();
        }

        pub fn getVersion(self: V5) Version {
            return self.toUuid().getVersion().?;
        }

        pub fn getSha1(self: V5) u122 {
            const low = self.getNative("sha1_low");
            const mid = self.getNative("sha1_mid");
            const high = self.getNative("sha1_high");

            return (@as(u122, high) << 74) | (@as(u122, mid) << 62) | low;
        }

        pub fn format(
            self: V5,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            return self.toUuid().format(fmt, options, writer);
        }

        fn getNative(self: V5, comptime field_name: []const u8) @FieldType(V5, field_name) {
            return readField(V5, field_name, &self);
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

            pub fn now() Timestamp {
                return ClockSequence(Timestamp).System.next();
            }
        };

        pub fn init(ts: Timestamp, node: u48) V6 {
            var self: V6 = undefined;

            writeField(V6, "node", &self, node);
            writeField(V6, "clock_seq", &self, ts.seq);
            writeField(V6, "variant", &self, 0b10);
            writeField(V6, "time_low", &self, @as(u12, @truncate(ts.tick)));
            writeField(V6, "version", &self, 6);
            writeField(V6, "time_mid", &self, @as(u16, @truncate(ts.tick >> 12)));
            writeField(V6, "time_high", &self, @as(u32, @truncate(ts.tick >> 28)));

            return self;
        }

        pub fn now(node: u48) V6 {
            return .init(.now(), node);
        }

        pub fn toUuid(self: V6) Uuid {
            return .{ .v6 = self };
        }

        pub fn toBytes(self: V6) [16]u8 {
            return @bitCast(self);
        }

        pub fn toNative(self: V6) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        pub fn toBig(self: V6) u128 {
            return @bitCast(self);
        }

        pub fn toLittle(self: V6) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        pub fn asBytes(self: *const V6) *const [16]u8 {
            return @ptrCast(self);
        }

        pub fn asSlice(self: V6) []u8 {
            return self.asBytes();
        }

        pub fn eql(self: V6, other: V6) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        pub fn order(self: V6, other: V6) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        pub fn getNode(self: V6) u48 {
            return self.getNative("node");
        }

        pub fn getClockSeq(self: V6) u14 {
            return self.getNative("clock_seq");
        }

        pub fn getVariant(self: V6) Variant {
            return self.toUuid().getVariant();
        }

        pub fn getVersion(self: V6) Version {
            return self.toUuid().getVersion().?;
        }

        pub fn getTime(self: V6) u60 {
            const low = self.getNative("time_low");
            const mid = self.getNative("time_mid");
            const high = self.getNative("time_high");

            return (@as(u60, high) << 28) | (@as(u60, mid) << 12) | low;
        }

        pub fn format(
            self: V6,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            return self.toUuid().format(fmt, options, writer);
        }

        fn getNative(self: V6, comptime field_name: []const u8) @FieldType(V6, field_name) {
            return readField(V6, field_name, &self);
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

            pub fn now() Timestamp {
                return ClockSequence(Timestamp).System.next();
            }
        };

        pub fn init(ts: Timestamp) V7 {
            var self: V7 = undefined;

            writeField(V7, "rand_b", &self, @as(u62, @truncate(ts.seq)));
            writeField(V7, "variant", &self, 0b10);
            writeField(V7, "rand_a", &self, @as(u12, @truncate(ts.seq >> 62)));
            writeField(V7, "version", &self, 7);
            writeField(V7, "unix_ts_ms", &self, ts.tick);

            return self;
        }

        pub fn now() V7 {
            return .init(.now());
        }

        pub fn toUuid(self: V7) Uuid {
            return .{ .v7 = self };
        }

        pub fn toBytes(self: V7) [16]u8 {
            return @bitCast(self);
        }

        pub fn toNative(self: V7) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        pub fn toBig(self: V7) u128 {
            return @bitCast(self);
        }

        pub fn toLittle(self: V7) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        pub fn asBytes(self: *const V7) *const [16]u8 {
            return @ptrCast(self);
        }

        pub fn asSlice(self: V7) []u8 {
            return self.asBytes();
        }

        pub fn eql(self: V7, other: V7) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        pub fn order(self: V7, other: V7) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        pub fn getUnixMs(self: V7) u48 {
            return self.getNative("unix_ts_ms");
        }

        pub fn getVariant(self: V7) Variant {
            return self.toUuid().getVariant();
        }

        pub fn getVersion(self: V7) Version {
            return self.toUuid().getVersion().?;
        }

        pub fn getRand(self: V7) u74 {
            const b = self.getNative("rand_b");
            const a = self.getNative("rand_a");

            return (@as(u74, a) << 62) | b;
        }

        pub fn format(
            self: V7,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            return self.toUuid().format(fmt, options, writer);
        }

        fn getNative(self: V7, comptime field_name: []const u8) @FieldType(V7, field_name) {
            return readField(V7, field_name, &self);
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

            writeField(V8, "custom_c", &self, @as(u62, @truncate(custom)));
            writeField(V8, "variant", &self, 0b10);
            writeField(V8, "custom_b", &self, @as(u12, @truncate(custom >> 62)));
            writeField(V8, "version", &self, 8);
            writeField(V8, "custom_a", &self, @as(u48, @truncate(custom >> 74)));

            return self;
        }

        pub fn toUuid(self: V8) Uuid {
            return .{ .v8 = self };
        }

        pub fn toBytes(self: V8) [16]u8 {
            return @bitCast(self);
        }

        pub fn toNative(self: V8) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        pub fn toBig(self: V8) u128 {
            return @bitCast(self);
        }

        pub fn toLittle(self: V8) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        pub fn asBytes(self: *const V8) *const [16]u8 {
            return @ptrCast(self);
        }

        pub fn asSlice(self: V8) []u8 {
            return self.asBytes();
        }

        pub fn eql(self: V8, other: V8) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        pub fn order(self: V8, other: V8) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        pub fn getVariant(self: V8) Variant {
            return self.toUuid().getVariant();
        }

        pub fn getVersion(self: V8) Version {
            return self.toUuid().getVersion().?;
        }

        pub fn getCustom(self: V8) u122 {
            const c = self.getNative("custom_c");
            const b = self.getNative("custom_b");
            const a = self.getNative("custom_a");

            return (@as(u122, a) << 74) | (@as(u122, b) << 62) | c;
        }

        pub fn format(
            self: V8,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            return self.toUuid().format(fmt, options, writer);
        }

        fn getNative(self: V8, comptime field_name: []const u8) @FieldType(V8, field_name) {
            return readField(V8, field_name, &self);
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

        pub var System: @This() = .{
            .clock = Clock.System,
            .rand = std.crypto.random,
        };

        pub var Zero: @This() = .{
            .clock = Clock.Zero,
            .rand = std.crypto.random,
        };

        clock: Clock,
        rand: Random,
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

const test_allocator = std.testing.allocator;

test "nil" {
    const uuid1 = Uuid.Nil;
    const uuid2 = Uuid{ .nil = .nil };
    const uuid3 = Uuid.fromNative(0);

    try std.testing.expect(uuid1.eql(uuid2));
    try std.testing.expect(uuid1.eql(uuid3));
    try std.testing.expect(uuid2.eql(uuid3));
}

test "max" {
    const uuid1 = Uuid.Max;
    const uuid2 = Uuid{ .max = .max };
    const uuid3 = Uuid.fromNative(std.math.maxInt(u128));

    try std.testing.expect(uuid1.eql(uuid2));
    try std.testing.expect(uuid1.eql(uuid3));
    try std.testing.expect(uuid2.eql(uuid3));
}

test "v1" {
    const ts = Uuid.V1.Timestamp.now();
    const uuid = Uuid.V1.init(ts, 69420);

    try std.testing.expectEqual(uuid.getVersion(), .v1);
    try std.testing.expectEqual(uuid.getVariant(), .rfc9562);
    try std.testing.expectEqual(uuid.getTime(), ts.tick);
    try std.testing.expectEqual(uuid.getClockSeq(), ts.seq);
    try std.testing.expectEqual(uuid.getNode(), 69420);
}

test "v3" {
    const uuid = Uuid.V3.init(Uuid.namespace.dns, "example.com");

    try std.testing.expectEqual(uuid.getVersion(), .v3);
    try std.testing.expectEqual(uuid.getVariant(), .rfc9562);
}

test "v4" {
    const uuid = Uuid.V4.init();

    try std.testing.expectEqual(uuid.getVersion(), .v4);
    try std.testing.expectEqual(uuid.getVariant(), .rfc9562);
}

test "v5" {
    const uuid = Uuid.V5.init(Uuid.namespace.dns, "example.com");

    try std.testing.expectEqual(uuid.getVersion(), .v5);
    try std.testing.expectEqual(uuid.getVariant(), .rfc9562);
}

test "v6" {
    const ts = Uuid.V6.Timestamp.now();
    const uuid = Uuid.V6.init(ts, 69420);

    try std.testing.expectEqual(uuid.getVersion(), .v6);
    try std.testing.expectEqual(uuid.getVariant(), .rfc9562);
    try std.testing.expectEqual(uuid.getTime(), ts.tick);
    try std.testing.expectEqual(uuid.getClockSeq(), ts.seq);
    try std.testing.expectEqual(uuid.getNode(), 69420);
}

test "v7" {
    const ts = Uuid.V7.Timestamp.now();
    const uuid = Uuid.V7.init(ts);

    try std.testing.expectEqual(uuid.getVersion(), .v7);
    try std.testing.expectEqual(uuid.getVariant(), .rfc9562);
    try std.testing.expectEqual(uuid.getUnixMs(), ts.tick);
    try std.testing.expectEqual(uuid.getRand(), ts.seq);
}

test "v8" {
    const custom = 0x123456789ABCDEF0123456789ABCDE;
    const uuid = Uuid.V8.init(custom);

    try std.testing.expectEqual(uuid.getVersion(), .v8);
    try std.testing.expectEqual(uuid.getVariant(), .rfc9562);
    try std.testing.expectEqual(uuid.getCustom(), custom);
}

test "equal" {
    const uuid1 = Uuid.fromNative(0x6ba7b810_9dad_11d1_80b4_00c04fd430c8);
    const uuid2 = Uuid.fromNative(0x6ba7b810_9dad_11d1_80b4_00c04fd430c8);
    const uuid3 = Uuid.fromNative(0xDEADBEEF_DEAD_BEEF_DEAD_BEEFDEADBEEF);

    try std.testing.expect(uuid1.eql(uuid2));
    try std.testing.expect(uuid2.eql(uuid1));
    try std.testing.expect(!uuid1.eql(uuid3));
    try std.testing.expect(!uuid2.eql(uuid3));
    try std.testing.expect(!uuid3.eql(uuid1));
    try std.testing.expect(!uuid3.eql(uuid2));
}

test "order" {
    const one = Uuid.V7.init(.now());
    const two = Uuid.V7.init(.now());

    try std.testing.expect(one.order(two) == .lt);
    try std.testing.expect(two.order(one) == .gt);
    try std.testing.expect(one.order(one) == .eq);
}

test "format" {
    const uuid = Uuid.fromNative(0x6ba7b810_9dad_11d1_80b4_00c04fd430c8);
    const actual = try std.fmt.allocPrint(test_allocator, "{}", .{uuid});
    defer test_allocator.free(actual);

    try std.testing.expectEqualStrings("6ba7b810-9dad-11d1-80b4-00c04fd430c8", actual);
}
