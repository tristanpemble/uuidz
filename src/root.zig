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
        const bytes = @as([16]u8, @bitCast(self));
        const value = std.mem.readPackedInt(u4, &bytes, 76, .big);

        // Versions are only meaningful and specified on RFC9562 compliant UUIDs.
        if (self.getVariant() != .rfc9562) {
            return switch (value) {
                0 => if (self.isNil()) .nil else null,
                15 => if (self.isMax()) .max else null,
                else => null,
            };
        }

        return switch (value) {
            1 => .v1,
            2 => .v2,
            3 => .v3,
            4 => .v4,
            5 => .v5,
            6 => .v6,
            7 => .v7,
            8 => .v8,
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

        pub fn asSlice(self: V1) []const u8 {
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

        pub fn asSlice(self: V2) []const u8 {
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
            return readField(V2, field_name, &self);
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
            writeField(V3, "md5_mid", &self, @as(u12, @truncate(md5 >> 64)));
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

        pub fn asSlice(self: V3) []const u8 {
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

        pub fn asSlice(self: V4) []const u8 {
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
            writeField(V5, "sha1_mid", &self, @as(u12, @truncate(sha1 >> 64)));
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

        pub fn asSlice(self: V5) []const u8 {
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

        pub fn asSlice(self: V6) []const u8 {
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

        pub fn asSlice(self: V7) []const u8 {
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

        pub fn asSlice(self: V8) []const u8 {
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

test "RFC9562 Test Vector A.1" {
    const uuid = Uuid.fromNative(0xC232AB00_9414_11EC_B3C8_9F6BDECED846);
    const formatted = try std.fmt.allocPrint(test_allocator, "{}", .{uuid});
    defer test_allocator.free(formatted);

    try std.testing.expectEqualStrings("c232ab00-9414-11ec-b3c8-9f6bdeced846", formatted);
    try std.testing.expectEqual(.rfc9562, uuid.getVariant());
    try std.testing.expectEqual(.v1, uuid.getVersion().?);

    try std.testing.expectEqual(0xC232AB00, uuid.v1.getNative("time_low"));
    try std.testing.expectEqual(0x9414, uuid.v1.getNative("time_mid"));
    try std.testing.expectEqual(0x1, uuid.v1.getNative("version"));
    try std.testing.expectEqual(0x1EC, uuid.v1.getNative("time_high"));
    try std.testing.expectEqual(0b10, uuid.v1.getNative("variant"));
    try std.testing.expectEqual(0x33C8, uuid.v1.getNative("clock_seq"));
    try std.testing.expectEqual(0x9F6BDECED846, uuid.v1.getNative("node"));
}

test "RFC9562 Test Vector A.2" {
    const ns = Uuid.fromNative(0x6ba7b810_9dad_11d1_80b4_00c04fd430c8);
    const uuid = Uuid{ .v3 = .init(ns, "www.example.com") };

    const formatted = try std.fmt.allocPrint(test_allocator, "{}", .{uuid});
    defer test_allocator.free(formatted);

    try std.testing.expectEqualStrings("5df41881-3aed-3515-88a7-2f4a814cf09e", formatted);
    try std.testing.expectEqual(.rfc9562, uuid.getVariant());
    try std.testing.expectEqual(.v3, uuid.getVersion().?);

    try std.testing.expectEqual(0x5df418813aed, uuid.v3.getNative("md5_high"));
    try std.testing.expectEqual(0x3, uuid.v3.getNative("version"));
    try std.testing.expectEqual(0x515, uuid.v3.getNative("md5_mid"));
    try std.testing.expectEqual(0b10, uuid.v3.getNative("variant"));
    try std.testing.expectEqual(0x08a72f4a814cf09e, uuid.v3.getNative("md5_low"));
}

test "RFC9562 Test Vector A.3" {
    const uuid = Uuid.fromNative(0x919108f7_52d1_4320_9bac_f847db4148a8);
    const formatted = try std.fmt.allocPrint(test_allocator, "{}", .{uuid});
    defer test_allocator.free(formatted);

    try std.testing.expectEqualStrings("919108f7-52d1-4320-9bac-f847db4148a8", formatted);
    try std.testing.expectEqual(.rfc9562, uuid.getVariant());
    try std.testing.expectEqual(.v4, uuid.getVersion().?);

    try std.testing.expectEqual(0x919108f752d1, uuid.v4.getNative("random_a"));
    try std.testing.expectEqual(0x4, uuid.v4.getNative("version"));
    try std.testing.expectEqual(0x320, uuid.v4.getNative("random_b"));
    try std.testing.expectEqual(0b10, uuid.v4.getNative("variant"));
    try std.testing.expectEqual(0x1bacf847db4148a8, uuid.v4.getNative("random_c"));
}

test "RFC9562 Test Vector A.4" {
    const ns = Uuid.fromNative(0x6ba7b810_9dad_11d1_80b4_00c04fd430c8);
    const uuid = Uuid{ .v5 = .init(ns, "www.example.com") };

    const formatted = try std.fmt.allocPrint(test_allocator, "{}", .{uuid});
    defer test_allocator.free(formatted);

    try std.testing.expectEqualStrings("2ed6657d-e927-568b-95e1-2665a8aea6a2", formatted);
    try std.testing.expectEqual(.rfc9562, uuid.getVariant());
    try std.testing.expectEqual(.v5, uuid.getVersion().?);

    try std.testing.expectEqual(0x2ed6657de927, uuid.v5.getNative("sha1_high"));
    try std.testing.expectEqual(0x5, uuid.v5.getNative("version"));
    try std.testing.expectEqual(0x68b, uuid.v5.getNative("sha1_mid"));
    try std.testing.expectEqual(0b10, uuid.v5.getNative("variant"));
    try std.testing.expectEqual(0x15e12665a8aea6a2, uuid.v5.getNative("sha1_low"));
}

test "RFC9562 Test Vector A.5" {
    const uuid = Uuid.fromNative(0x1EC9414C_232A_6B00_B3C8_9F6BDECED846);
    const formatted = try std.fmt.allocPrint(test_allocator, "{}", .{uuid});
    defer test_allocator.free(formatted);

    try std.testing.expectEqualStrings("1ec9414c-232a-6b00-b3c8-9f6bdeced846", formatted);
    try std.testing.expectEqual(.rfc9562, uuid.getVariant());
    try std.testing.expectEqual(.v6, uuid.getVersion().?);

    try std.testing.expectEqual(0x1EC9414C, uuid.v6.getNative("time_high"));
    try std.testing.expectEqual(0x232A, uuid.v6.getNative("time_mid"));
    try std.testing.expectEqual(0x6, uuid.v6.getNative("version"));
    try std.testing.expectEqual(0xB00, uuid.v6.getNative("time_low"));
    try std.testing.expectEqual(0b10, uuid.v6.getNative("variant"));
    try std.testing.expectEqual(0x33C8, uuid.v6.getNative("clock_seq"));
    try std.testing.expectEqual(0x9F6BDECED846, uuid.v6.getNative("node"));
}

test "RFC9562 Test Vector A.6" {
    const uuid = Uuid.fromNative(0x017F22E2_79B0_7CC3_98C4_DC0C0C07398F);
    const formatted = try std.fmt.allocPrint(test_allocator, "{}", .{uuid});
    defer test_allocator.free(formatted);

    try std.testing.expectEqualStrings("017f22e2-79b0-7cc3-98c4-dc0c0c07398f", formatted);
    try std.testing.expectEqual(.rfc9562, uuid.getVariant());
    try std.testing.expectEqual(.v7, uuid.getVersion().?);

    try std.testing.expectEqual(0x017F22E279B0, uuid.v7.getNative("unix_ts_ms"));
    try std.testing.expectEqual(0x7, uuid.v7.getNative("version"));
    try std.testing.expectEqual(0xCC3, uuid.v7.getNative("rand_a"));
    try std.testing.expectEqual(0b10, uuid.v7.getNative("variant"));
    try std.testing.expectEqual(0x18C4DC0C0C07398F, uuid.v7.getNative("rand_b"));
}

test "RFC9562 Test Vector B.1" {
    const uuid = Uuid.fromNative(0x2489E9AD_2EE2_8E00_8EC9_32D5F69181C0);
    const formatted = try std.fmt.allocPrint(test_allocator, "{}", .{uuid});
    defer test_allocator.free(formatted);

    try std.testing.expectEqualStrings("2489e9ad-2ee2-8e00-8ec9-32d5f69181c0", formatted);
    try std.testing.expectEqual(.rfc9562, uuid.getVariant());
    try std.testing.expectEqual(.v8, uuid.getVersion().?);

    try std.testing.expectEqual(0x2489E9AD2EE2, uuid.v8.getNative("custom_a"));
    try std.testing.expectEqual(0x8, uuid.v8.getNative("version"));
    try std.testing.expectEqual(0xE00, uuid.v8.getNative("custom_b"));
    try std.testing.expectEqual(0b10, uuid.v8.getNative("variant"));
    try std.testing.expectEqual(0x0EC932D5F69181C0, uuid.v8.getNative("custom_c"));
}

test "RFC9562 Test Vector B.2" {
    const uuid = Uuid.fromNative(0x5c146b14_3c52_8afd_938a_375d0df1fbf6);
    const formatted = try std.fmt.allocPrint(test_allocator, "{}", .{uuid});
    defer test_allocator.free(formatted);

    try std.testing.expectEqualStrings("5c146b14-3c52-8afd-938a-375d0df1fbf6", formatted);
    try std.testing.expectEqual(.rfc9562, uuid.getVariant());
    try std.testing.expectEqual(.v8, uuid.getVersion().?);

    try std.testing.expectEqual(0x5c146b143c52, uuid.v8.getNative("custom_a"));
    try std.testing.expectEqual(0x8, uuid.v8.getNative("version"));
    try std.testing.expectEqual(0xafd, uuid.v8.getNative("custom_b"));
    try std.testing.expectEqual(0b10, uuid.v8.getNative("variant"));
    try std.testing.expectEqual(0x138a375d0df1fbf6, uuid.v8.getNative("custom_c"));
}

test "nil and max special values" {
    // Test nil UUID
    const nil1 = Uuid.Nil;
    const nil2 = Uuid{ .nil = .nil };
    const nil3 = Uuid.fromNative(0);

    try std.testing.expect(nil1.eql(nil2));
    try std.testing.expect(nil1.eql(nil3));
    try std.testing.expect(nil1.isNil());
    try std.testing.expect(!nil1.isMax());
    try std.testing.expectEqual(.nil, nil1.getVersion());

    // Test max UUID
    const max1 = Uuid.Max;
    const max2 = Uuid{ .max = .max };
    const max3 = Uuid.fromNative(std.math.maxInt(u128));

    try std.testing.expect(max1.eql(max2));
    try std.testing.expect(max1.eql(max3));
    try std.testing.expect(max1.isMax());
    try std.testing.expect(!max1.isNil());
    try std.testing.expectEqual(.max, max1.getVersion());

    // Test ordering
    try std.testing.expectEqual(.lt, nil1.order(max1));
    try std.testing.expectEqual(.gt, max1.order(nil1));
}

test "equality and formatting" {
    const uuid1 = Uuid.fromNative(0x6ba7b810_9dad_11d1_80b4_00c04fd430c8);
    const uuid2 = Uuid.fromNative(0x6ba7b810_9dad_11d1_80b4_00c04fd430c8);
    const uuid3 = Uuid.fromNative(0xDEADBEEF_DEAD_BEEF_DEAD_BEEFDEADBEEF);

    // Test equality
    try std.testing.expect(uuid1.eql(uuid2));
    try std.testing.expect(!uuid1.eql(uuid3));

    // Test formatting
    const formatted = try std.fmt.allocPrint(test_allocator, "{}", .{uuid1});
    defer test_allocator.free(formatted);
    try std.testing.expectEqualStrings("6ba7b810-9dad-11d1-80b4-00c04fd430c8", formatted);
}

test "version field compliance" {
    inline for ([_]type{ Uuid.V1, Uuid.V2, Uuid.V3, Uuid.V4, Uuid.V5, Uuid.V6, Uuid.V7, Uuid.V8 }, 1..) |V, version_number| {
        if (version_number == 2) continue;

        const uuid = switch (V) {
            Uuid.V1 => V.now(0x123456789ABC),
            Uuid.V2 => unreachable,
            Uuid.V3 => V.init(Uuid.namespace.dns, "test"),
            Uuid.V4 => V.init(),
            Uuid.V5 => V.init(Uuid.namespace.dns, "test"),
            Uuid.V6 => V.now(0x123456789ABC),
            Uuid.V7 => V.now(),
            Uuid.V8 => V.init(0x123456789ABCDEF0123456789ABCDE),
            else => unreachable,
        };

        try std.testing.expectEqual(@as(u8, version_number), @intFromEnum(uuid.getVersion()));
        try std.testing.expectEqual(Uuid.Variant.rfc9562, uuid.getVariant());
    }
}

test "variant field compliance" {
    // Test all variant patterns according to RFC 9562:
    // https://www.rfc-editor.org/rfc/rfc9562.html#name-variant-field
    const test_cases = [_]struct { byte: u8, expected: Uuid.Variant }{
        .{ .byte = 0b00000000, .expected = .ncs },
        .{ .byte = 0b01111111, .expected = .ncs },
        .{ .byte = 0b10000000, .expected = .rfc9562 },
        .{ .byte = 0b10111111, .expected = .rfc9562 },
        .{ .byte = 0b11000000, .expected = .microsoft },
        .{ .byte = 0b11011111, .expected = .microsoft },
        .{ .byte = 0b11100000, .expected = .future },
        .{ .byte = 0b11101111, .expected = .future },
        .{ .byte = 0b11111111, .expected = .future },
    };

    inline for (test_cases) |case| {
        var bytes = [_]u8{0} ** 16;
        bytes[8] = case.byte;

        const uuid = Uuid.fromBytes(bytes);

        try std.testing.expectEqual(case.expected, uuid.getVariant());
    }
}

test "endianness consistency" {
    const int: u128 = 0x0123456789ABCDEF_FEDCBA9876543210;

    const native = Uuid.fromNative(int);
    const big = Uuid.fromBig(int);
    const little = Uuid.fromLittle(int);

    // Round-trip tests
    try std.testing.expectEqual(int, native.toNative());
    try std.testing.expectEqual(int, big.toBig());
    try std.testing.expectEqual(int, little.toLittle());

    // Cross-conversion consistency
    try std.testing.expectEqual(big.toLittle(), little.toBig());
}

test "byte array round trip" {
    const expected = [_]u8{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0xFE, 0xDC, 0xBA, 0x98, 0x76, 0x54, 0x32, 0x10 };

    const uuid = Uuid.fromBytes(expected);
    const actual = uuid.toBytes();

    try std.testing.expectEqualSlices(u8, &expected, &actual);
}

test "clock sequence rollover" {
    // Test that clock sequence increments when generating timestamps at the same tick
    inline for ([_]type{ Uuid.V1.Timestamp, Uuid.V6.Timestamp, Uuid.V7.Timestamp }) |Timestamp| {
        var seq = ClockSequence(Timestamp).Zero;

        const ts1 = seq.next();
        const ts2 = seq.next();
        const ts3 = seq.next();

        try std.testing.expectEqual(ts1.tick, ts2.tick);
        try std.testing.expectEqual(ts2.tick, ts3.tick);
        try std.testing.expect(ts2.seq == ts1.seq +% 1);
        try std.testing.expect(ts3.seq == ts2.seq +% 1);
    }
}

test "v7 ordering" {
    var seq = ClockSequence(Uuid.V7.Timestamp).Zero;

    const ts1 = seq.next();
    var ts2 = seq.next();
    ts2.tick += std.time.ns_per_ms;

    const one = Uuid.V7.init(ts1);
    const two = Uuid.V7.init(ts2);

    try std.testing.expectEqual(.lt, one.order(two));
    try std.testing.expectEqual(.gt, two.order(one));
    try std.testing.expectEqual(.eq, one.order(one));

    try std.testing.expect(one.getUnixMs() < two.getUnixMs());
    try std.testing.expectEqual(std.time.ns_per_ms, two.getUnixMs() - one.getUnixMs());
}



test "v3 v5 deterministic" {
    const name = "test.example.com";
    const ns = Uuid.namespace.dns;

    const v3_1 = Uuid.V3.init(ns, name);
    const v3_2 = Uuid.V3.init(ns, name);
    const v5_1 = Uuid.V5.init(ns, name);
    const v5_2 = Uuid.V5.init(ns, name);

    try std.testing.expect(v3_1.eql(v3_2));
    try std.testing.expect(v5_1.eql(v5_2));
    try std.testing.expect(!v3_1.toUuid().eql(v5_1.toUuid())); // Different algorithms
}

test "v3 v5 namespace sensitivity" {
    const name = "example.com";

    const v3_dns = Uuid.V3.init(Uuid.namespace.dns, name);
    const v3_url = Uuid.V3.init(Uuid.namespace.url, name);
    const v5_dns = Uuid.V5.init(Uuid.namespace.dns, name);
    const v5_url = Uuid.V5.init(Uuid.namespace.url, name);

    try std.testing.expect(!v3_dns.eql(v3_url));
    try std.testing.expect(!v5_dns.eql(v5_url));
}

test "v4 randomness" {
    // Test that V4 UUIDs are unique across a reasonable sample
    var seen = std.AutoHashMap([16]u8, void).init(test_allocator);
    defer seen.deinit();

    for (0..10_000) |_| {
        const uuid = Uuid.V4.init();
        const bytes = uuid.toBytes();
        try std.testing.expect(!seen.contains(bytes));
        try seen.put(bytes, {});
    }
}



test "field extraction and union conversions" {
    // Test V1 field extraction
    const node: u48 = 0x123456789ABC;
    const clock_seq: u14 = 0x1234;
    const time_tick: u60 = 0x123456789ABCDEF;

    const ts = Uuid.V1.Timestamp{ .tick = time_tick, .seq = clock_seq };
    const v1 = Uuid.V1.init(ts, node);

    try std.testing.expectEqual(node, v1.getNode());
    try std.testing.expectEqual(clock_seq, v1.getClockSeq());
    try std.testing.expectEqual(time_tick, v1.getTime());

    // Test union conversion preserves data
    const v1_uuid = v1.toUuid();
    try std.testing.expectEqual(Uuid.Version.v1, v1_uuid.getVersion().?);
    try std.testing.expectEqual(Uuid.Variant.rfc9562, v1_uuid.getVariant());
    try std.testing.expectEqualSlices(u8, &v1.toBytes(), &v1_uuid.toBytes());

    // Test V8 custom data
    const custom = 0x123456789ABCDEF0123456789ABCDE;
    const v8 = Uuid.V8.init(custom);
    try std.testing.expectEqual(custom, v8.getCustom());
    try std.testing.expectEqual(.v8, v8.toUuid().getVersion().?);
}

test "version-specific creation" {
    // V1 with timestamp and node
    const node: u48 = 0x123456789ABC;
    const v1_ts = Uuid.V1.Timestamp.now();
    const v1 = Uuid.V1.init(v1_ts, node);
    try std.testing.expectEqual(.v1, v1.getVersion());
    try std.testing.expectEqual(.rfc9562, v1.getVariant());
    try std.testing.expectEqual(node, v1.getNode());

    // V3 with namespace and name
    const v3 = Uuid.V3.init(Uuid.namespace.dns, "example.com");
    try std.testing.expectEqual(.v3, v3.getVersion());
    try std.testing.expectEqual(.rfc9562, v3.getVariant());

    // V4 random
    const v4 = Uuid.V4.init();
    try std.testing.expectEqual(.v4, v4.getVersion());
    try std.testing.expectEqual(.rfc9562, v4.getVariant());

    // V5 with namespace and name
    const v5 = Uuid.V5.init(Uuid.namespace.url, "https://example.com");
    try std.testing.expectEqual(.v5, v5.getVersion());
    try std.testing.expectEqual(.rfc9562, v5.getVariant());

    // V6 with timestamp and node
    const v6_ts = Uuid.V6.Timestamp.now();
    const v6 = Uuid.V6.init(v6_ts, node);
    try std.testing.expectEqual(.v6, v6.getVersion());
    try std.testing.expectEqual(.rfc9562, v6.getVariant());
    try std.testing.expectEqual(node, v6.getNode());

    // V7 with timestamp
    const v7_ts = Uuid.V7.Timestamp.now();
    const v7 = Uuid.V7.init(v7_ts);
    try std.testing.expectEqual(.v7, v7.getVersion());
    try std.testing.expectEqual(.rfc9562, v7.getVariant());

    // V8 with custom data
    const custom_data = 0x123456789ABCDEF0123456789ABCDE;
    const v8 = Uuid.V8.init(custom_data);
    try std.testing.expectEqual(.v8, v8.getVersion());
    try std.testing.expectEqual(.rfc9562, v8.getVariant());
    try std.testing.expectEqual(custom_data, v8.getCustom());
}

test "namespace UUIDs" {
    // Test predefined namespaces are correctly formatted
    const dns_formatted = try std.fmt.allocPrint(test_allocator, "{}", .{Uuid.namespace.dns});
    defer test_allocator.free(dns_formatted);
    try std.testing.expectEqualStrings("6ba7b810-9dad-11d1-80b4-00c04fd430c8", dns_formatted);

    const url_formatted = try std.fmt.allocPrint(test_allocator, "{}", .{Uuid.namespace.url});
    defer test_allocator.free(url_formatted);
    try std.testing.expectEqualStrings("6ba7b811-9dad-11d1-80b4-00c04fd430c8", url_formatted);

    // Test that all namespaces are different
    try std.testing.expect(!Uuid.namespace.dns.eql(Uuid.namespace.url));
    try std.testing.expect(!Uuid.namespace.dns.eql(Uuid.namespace.oid));
    try std.testing.expect(!Uuid.namespace.dns.eql(Uuid.namespace.x500));
    try std.testing.expect(!Uuid.namespace.url.eql(Uuid.namespace.oid));
    try std.testing.expect(!Uuid.namespace.url.eql(Uuid.namespace.x500));
    try std.testing.expect(!Uuid.namespace.oid.eql(Uuid.namespace.x500));
}

test "conversion round trips" {
    const original = Uuid.fromNative(0x0123456789ABCDEF_FEDCBA9876543210);

    // Native conversion round trip
    try std.testing.expectEqual(original.toNative(), Uuid.fromNative(original.toNative()).toNative());

    // Big endian conversion round trip
    try std.testing.expect(original.eql(Uuid.fromBig(original.toBig())));

    // Little endian conversion round trip
    try std.testing.expect(original.eql(Uuid.fromLittle(original.toLittle())));

    // Bytes conversion round trip
    try std.testing.expect(original.eql(Uuid.fromBytes(original.toBytes())));

    // Cross-endian consistency
    const from_big = Uuid.fromBig(0x0123456789ABCDEF_FEDCBA9876543210);
    const from_little = Uuid.fromLittle(0x0123456789ABCDEF_FEDCBA9876543210);
    try std.testing.expectEqual(from_big.toBig(), 0x0123456789ABCDEF_FEDCBA9876543210);
    try std.testing.expectEqual(from_little.toLittle(), 0x0123456789ABCDEF_FEDCBA9876543210);
}

test "ordering comprehensive" {
    const uuid_low = Uuid.fromNative(0x00000000_0000_0000_0000_000000000001);
    const uuid_mid = Uuid.fromNative(0x12345678_9ABC_DEF0_1234_56789ABCDEF0);
    const uuid_high = Uuid.fromNative(0xFFFFFFFF_FFFF_FFFF_FFFF_FFFFFFFFFFFE);

    // Test basic ordering
    try std.testing.expectEqual(.lt, uuid_low.order(uuid_mid));
    try std.testing.expectEqual(.lt, uuid_mid.order(uuid_high));
    try std.testing.expectEqual(.lt, uuid_low.order(uuid_high));

    // Test reverse ordering
    try std.testing.expectEqual(.gt, uuid_high.order(uuid_mid));
    try std.testing.expectEqual(.gt, uuid_mid.order(uuid_low));
    try std.testing.expectEqual(.gt, uuid_high.order(uuid_low));

    // Test equality
    try std.testing.expectEqual(.eq, uuid_mid.order(uuid_mid));

    // Test with special values
    try std.testing.expectEqual(.lt, Uuid.Nil.order(uuid_low));
    try std.testing.expectEqual(.gt, Uuid.Max.order(uuid_high));
}

test "clock sequence edge cases" {
    // Test sequence overflow behavior
    var seq = ClockSequence(Uuid.V7.Timestamp).Zero;
    
    // Force sequence to near overflow
    seq.seq = std.math.maxInt(@TypeOf(seq.seq)) - 1;
    
    const ts1 = seq.next();
    const ts2 = seq.next(); // Should wrap around
    const ts3 = seq.next();
    
    try std.testing.expectEqual(ts1.tick, ts2.tick);
    try std.testing.expectEqual(ts2.tick, ts3.tick);
    try std.testing.expect(ts2.seq == ts1.seq +% 1);
    try std.testing.expect(ts3.seq == ts2.seq +% 1);
}

test "format edge cases" {
    // Test formatting with all zeros and all ones
    const all_zeros = Uuid.Nil;
    const zeros_str = try std.fmt.allocPrint(test_allocator, "{}", .{all_zeros});
    defer test_allocator.free(zeros_str);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000000", zeros_str);

    const all_ones = Uuid.Max;
    const ones_str = try std.fmt.allocPrint(test_allocator, "{}", .{all_ones});
    defer test_allocator.free(ones_str);
    try std.testing.expectEqualStrings("ffffffff-ffff-ffff-ffff-ffffffffffff", ones_str);

    // Test that format length is always consistent
    for (0..100) |_| {
        const random_uuid = Uuid.V4.init();
        const formatted = try std.fmt.allocPrint(test_allocator, "{}", .{random_uuid});
        defer test_allocator.free(formatted);
        try std.testing.expectEqual(36, formatted.len); // Standard UUID string length
        
        // Verify format structure (8-4-4-4-12)
        try std.testing.expectEqual('-', formatted[8]);
        try std.testing.expectEqual('-', formatted[13]);
        try std.testing.expectEqual('-', formatted[18]);
        try std.testing.expectEqual('-', formatted[23]);
    }
}
