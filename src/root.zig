//! An RFC 9562 compliant UUID library with a union-based design for type safety.
//!
//! Features:
//! - All UUID versions (1-8) with version-specific types.
//! - Thread-safe and single-threaded clock sequence generators.
//! - Standard namespace UUIDs and special values (nil, max).
//! - Parsing, formatting, and conversion utilities.
//! - Zero-allocation design with packed struct layouts.

const builtin = @import("builtin");
const std = @import("std");

const Random = std.Random;
const Md5 = std.crypto.hash.Md5;
const Sha1 = std.crypto.hash.Sha1;

const native_endian = builtin.target.cpu.arch.endian();

// The number of 100ns ticks from 15 Oct 1582 to 1 Jan 1970.
const greg_unix_offset = 0x01B21DD213814000;

/// An RFC 9562 UUID implementation with a union-based design for type-safe version handling.
/// This supports all versions (1-8) through both a unified interface and version-specific types.
pub const Uuid = packed union {
    v1: V1,
    v2: V2,
    v3: V3,
    v4: V4,
    v5: V5,
    v6: V6,
    v7: V7,
    v8: V8,

    /// The nil UUID (all zeros) as defined in RFC 9562
    pub const nil: Uuid = .fromNative(0x00000000_0000_0000_0000_000000000000);
    /// The max UUID (all ones) as defined in RFC 9562
    pub const max: Uuid = .fromNative(0xffffffff_ffff_ffff_ffff_ffffffffffff);

    /// The standard namespace for DNS names.
    pub const dns: Uuid = Uuid.fromNative(0x6ba7b810_9dad_11d1_80b4_00c04fd430c8);
    /// The standard namespace for URLs.
    pub const url: Uuid = Uuid.fromNative(0x6ba7b811_9dad_11d1_80b4_00c04fd430c8);
    /// The standard namespace for ISO OIDs.
    pub const oid: Uuid = Uuid.fromNative(0x6ba7b812_9dad_11d1_80b4_00c04fd430c8);
    /// The standard namespace for X.500 Distinguished Names.
    pub const x500: Uuid = Uuid.fromNative(0x6ba7b814_9dad_11d1_80b4_00c04fd430c8);

    /// Parse a UUID from the standard string format.
    pub fn parse(input: []const u8) !Uuid {
        if (input.len != 36) return error.InvalidFormat;

        if (input[8] != '-' or input[13] != '-' or input[18] != '-' or input[23] != '-') {
            return error.InvalidFormat;
        }

        const ctod = struct {
            fn ctod(c: u8) !u8 {
                return switch (c) {
                    '0'...'9' => c - '0',
                    'A'...'F' => c - 'A' + 10,
                    'a'...'f' => c - 'a' + 10,
                    else => return error.InvalidFormat,
                };
            }
        }.ctod;

        return Uuid.fromBytes([16]u8{
            (try ctod(input[0]) << 4) | try ctod(input[1]),
            (try ctod(input[2]) << 4) | try ctod(input[3]),
            (try ctod(input[4]) << 4) | try ctod(input[5]),
            (try ctod(input[6]) << 4) | try ctod(input[7]),
            (try ctod(input[9]) << 4) | try ctod(input[10]),
            (try ctod(input[11]) << 4) | try ctod(input[12]),
            (try ctod(input[14]) << 4) | try ctod(input[15]),
            (try ctod(input[16]) << 4) | try ctod(input[17]),
            (try ctod(input[19]) << 4) | try ctod(input[20]),
            (try ctod(input[21]) << 4) | try ctod(input[22]),
            (try ctod(input[24]) << 4) | try ctod(input[25]),
            (try ctod(input[26]) << 4) | try ctod(input[27]),
            (try ctod(input[28]) << 4) | try ctod(input[29]),
            (try ctod(input[30]) << 4) | try ctod(input[31]),
            (try ctod(input[32]) << 4) | try ctod(input[33]),
            (try ctod(input[34]) << 4) | try ctod(input[35]),
        });
    }

    /// Format this UUID as the standard string.
    pub fn toString(self: Uuid) [36]u8 {
        const bytes = self.toBytes();
        const charset = std.fmt.hex_charset;

        var result: [36]u8 = undefined;

        inline for (0..4) |i| {
            result[i * 2 + 0] = charset[bytes[i] >> 4];
            result[i * 2 + 1] = charset[bytes[i] & 15];
        }

        result[8] = '-';

        inline for (4..6) |i| {
            const pos = (i - 4) * 2 + 9;
            result[pos + 0] = charset[bytes[i] >> 4];
            result[pos + 1] = charset[bytes[i] & 15];
        }

        result[13] = '-';

        inline for (6..8) |i| {
            const pos = (i - 6) * 2 + 14;
            result[pos + 0] = charset[bytes[i] >> 4];
            result[pos + 1] = charset[bytes[i] & 15];
        }

        result[18] = '-';

        inline for (8..10) |i| {
            const pos = (i - 8) * 2 + 19;
            result[pos + 0] = charset[bytes[i] >> 4];
            result[pos + 1] = charset[bytes[i] & 15];
        }

        result[23] = '-';

        inline for (10..16) |i| {
            const pos = (i - 10) * 2 + 24;
            result[pos + 0] = charset[bytes[i] >> 4];
            result[pos + 1] = charset[bytes[i] & 15];
        }

        return result;
    }

    /// Create a UUID from a big-endian byte array.
    pub fn fromBytes(bytes: [16]u8) Uuid {
        return @bitCast(bytes);
    }

    /// Create a UUID from a native-endian u128 value.
    pub fn fromNative(value: u128) Uuid {
        return switch (native_endian) {
            .big => fromBig(value),
            .little => fromLittle(value),
        };
    }

    /// Create a UUID from big-endian u128 value
    pub fn fromBig(value: u128) Uuid {
        return @bitCast(@as(u128, @intCast(value)));
    }

    /// Create a UUID from little-endian u128 value
    pub fn fromLittle(value: u128) Uuid {
        return @bitCast(@byteSwap(@as(u128, @intCast(value))));
    }

    /// Convert this UUID to big-endian byte array
    pub fn toBytes(self: Uuid) [16]u8 {
        return @bitCast(self);
    }

    /// Convert this UUID to native-endian u128 value
    pub fn toNative(self: Uuid) u128 {
        return switch (native_endian) {
            .little => self.toLittle(),
            .big => self.toBig(),
        };
    }

    /// Convert this UUID to big-endian u128 value
    pub fn toBig(self: Uuid) u128 {
        return @bitCast(self);
    }

    /// Convert this UUID to little-endian u128 value
    pub fn toLittle(self: Uuid) u128 {
        return @byteSwap(@as(u128, @bitCast(self)));
    }

    /// Get a pointer to UUID bytes
    pub fn asBytes(self: *const Uuid) *const [16]u8 {
        return @ptrCast(self);
    }

    /// Get this UUID as byte slice
    pub fn asSlice(self: *const Uuid) []const u8 {
        return self.asBytes();
    }

    /// Test equality with another UUID.
    pub fn eql(self: Uuid, other: Uuid) bool {
        return std.mem.eql(u8, self.asSlice(), other.asSlice());
    }

    /// Compare ordering with another UUID.
    pub fn order(self: Uuid, other: Uuid) std.math.Order {
        return std.mem.order(u8, self.asSlice(), other.asSlice());
    }

    /// Extract the version field (4 bits at offset 48-51).
    ///
    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-version-field
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

    /// Extract the variant field (variable length at offset 64-65+).
    ///
    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-variant-field
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

    /// Test if UUID is the nil UUID (all zeros)
    pub fn isNil(self: Uuid) bool {
        return self.eql(nil);
    }

    /// Test if UUID is the max UUID (all ones)
    pub fn isMax(self: Uuid) bool {
        return self.eql(max);
    }

    /// UUID version identifiers as defined in RFC 9562.
    pub const Version = enum(u4) {
        /// Special nil UUID (all zeros)
        nil = 0b0000,
        /// Time-based UUID with MAC address
        v1 = 1,
        /// DCE Security UUID (rarely used)
        v2 = 2,
        /// Name-based UUID using MD5 hash
        v3 = 3,
        /// Random or pseudo-random UUID
        v4 = 4,
        /// Name-based UUID using SHA-1 hash
        v5 = 5,
        /// Reordered time-based UUID with MAC address
        v6 = 6,
        /// Unix timestamp-based UUID with random data
        v7 = 7,
        /// Custom/experimental UUID format
        v8 = 8,
        /// Special max UUID (all ones)
        max = 0b1111,

        /// Alias for v1 (time-based UUID with MAC address)
        pub const mac = Version.v1;
        /// Alias for v2 (DCE Security UUID)
        pub const dce = Version.v2;
        /// Alias for v3 (name-based UUID using MD5 hash)
        pub const md5 = Version.v3;
        /// Alias for v4 (random or pseudo-random UUID)
        pub const random = Version.v4;
        /// Alias for v5 (name-based UUID using SHA-1 hash)
        pub const sha1 = Version.v5;
        /// Alias for v6 (reordered time-based UUID with MAC address)
        pub const sort_mac = Version.v6;
        /// Alias for v7 (Unix timestamp-based UUID with random data)
        pub const sort_rand = Version.v7;
        /// Alias for v8 (custom/experimental UUID format)
        pub const custom = Version.v8;
    };

    /// UUID variant field values.
    pub const Variant = enum {
        /// NCS/Reserved
        ncs,
        /// RFC 9562 variant (most common)
        rfc9562,
        /// Microsoft variant
        microsoft,
        /// Future use
        future,
    };

    /// Version 1: Gregorian time + node ID (MAC address).
    /// Time-ordered but reveals the MAC address and creation time.
    ///
    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-1
    pub const V1 = packed struct(u128) {
        /// The 48-bit node ID (typically a MAC address).
        node: u48,
        /// The 14-bit clock sequence for collision avoidance.
        clock_seq: u14,
        /// The 2-bit variant field (should be 0b10).
        variant: u2,
        /// The high 12 bits of the 60-bit timestamp.
        time_high: u12,
        /// The 4-bit version field (should be 1).
        version: u4,
        /// The middle 16 bits of the 60-bit timestamp.
        time_mid: u16,
        /// The low 32 bits of the 60-bit timestamp.
        time_low: u32,

        /// The timestamp structure for V1 UUIDs.
        pub const Timestamp = struct {
            /// The number of nanoseconds per tick (100ns intervals since 1582-10-15).
            pub const ns_per_tick = 100;
            /// The nanosecond offset from the Gregorian epoch to the Unix epoch.
            pub const ns_unix_offset = greg_unix_offset * ns_per_tick;
            /// The 60-bit timestamp in 100ns ticks since 1582-10-15.
            tick: u60,
            /// The 14-bit clock sequence.
            seq: u14,

            /// Get the current timestamp with thread-safe clock sequence.
            pub fn safe() Timestamp {
                return SafeClockSequence(Timestamp).System.next();
            }

            /// Get the current timestamp with singled-threaded sequential clock sequence.
            pub fn fast() Timestamp {
                return FastClockSequence(Timestamp).System.next();
            }
        };

        /// Create a V1 UUID from a timestamp and node ID.
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

        /// Create a V1 UUID with the current timestamp and node ID.
        pub fn now(node: u48) V1 {
            return .init(.safe(), node);
        }

        /// Convert to the generic Uuid union type.
        pub fn toUuid(self: V1) Uuid {
            return .{ .v1 = self };
        }

        /// Convert to a big-endian byte array.
        pub fn toBytes(self: V1) [16]u8 {
            return @bitCast(self);
        }

        /// Convert to a native-endian u128.
        pub fn toNative(self: V1) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        /// Convert to a big-endian u128.
        pub fn toBig(self: V1) u128 {
            return @bitCast(self);
        }

        /// Convert to a little-endian u128.
        pub fn toLittle(self: V1) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        /// Format as the standard UUID string.
        pub fn toString(self: V1) [36]u8 {
            return self.toUuid().toString();
        }

        /// Get a pointer to the underlying bytes.
        pub fn asBytes(self: *const V1) *const [16]u8 {
            return @ptrCast(self);
        }

        /// Get a slice view of the underlying bytes.
        pub fn asSlice(self: V1) []const u8 {
            return self.asBytes();
        }

        /// Test equality with another V1 UUID.
        pub fn eql(self: V1, other: V1) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        /// Compare ordering with another V1 UUID.
        pub fn order(self: V1, other: V1) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        /// Extract the node ID field.
        pub fn getNode(self: V1) u48 {
            return self.getNative("node");
        }

        /// Extract the clock sequence field.
        pub fn getClockSeq(self: V1) u14 {
            return self.getNative("clock_seq");
        }

        /// Extract the variant field.
        pub fn getVariant(self: V1) Variant {
            return self.toUuid().getVariant();
        }

        /// Extract the version field.
        pub fn getVersion(self: V1) Version {
            return self.toUuid().getVersion().?;
        }

        /// Extract the 60-bit timestamp field.
        pub fn getTime(self: V1) u60 {
            const low = self.getNative("time_low");
            const mid = self.getNative("time_mid");
            const high = self.getNative("time_high");

            return (@as(u60, high) << 48) | (@as(u60, mid) << 32) | low;
        }

        /// Format for std.fmt (delegates to toString).
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

    /// Version 2: DCE Security UUID.
    /// Reserved for DCE security, rarely used in practice.
    ///
    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-2
    pub const V2 = packed struct(u128) {
        /// The low 62 bits of DCE data.
        low: u62,
        /// The 2-bit variant field (should be 0b10).
        variant: u2,
        /// The middle 12 bits of DCE data.
        mid: u12,
        /// The 4-bit version field (should be 2).
        version: u4,
        /// The high 48 bits of DCE data.
        high: u48,

        /// Convert to the generic Uuid union type.
        pub fn toUuid(self: V2) Uuid {
            return .{ .v2 = self };
        }

        /// Convert to a big-endian byte array.
        pub fn toBytes(self: V2) [16]u8 {
            return @bitCast(self);
        }

        /// Convert to a native-endian u128.
        pub fn toNative(self: V2) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        /// Convert to a big-endian u128.
        pub fn toBig(self: V2) u128 {
            return @bitCast(self);
        }

        /// Convert to a little-endian u128.
        pub fn toLittle(self: V2) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        /// Format as the standard UUID string.
        pub fn toString(self: V2) [36]u8 {
            return self.toUuid().toString();
        }

        /// Get a pointer to the underlying bytes.
        pub fn asBytes(self: *const V2) *const [16]u8 {
            return @ptrCast(self);
        }

        /// Get a slice view of the underlying bytes.
        pub fn asSlice(self: V2) []const u8 {
            return self.asBytes();
        }

        /// Test equality with another V2 UUID.
        pub fn eql(self: V2, other: V2) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        /// Compare ordering with another V2 UUID.
        pub fn order(self: V2, other: V2) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        /// Extract the variant field.
        pub fn getVariant(self: V2) Variant {
            return self.toUuid().getVariant();
        }

        /// Extract the version field.
        pub fn getVersion(self: V2) Version {
            return self.toUuid().getVersion().?;
        }

        /// Extract the low 62 bits.
        pub fn getLow(self: V2) u62 {
            return self.getNative("low");
        }

        /// Extract the middle 12 bits.
        pub fn getMid(self: V2) u12 {
            return self.getNative("mid");
        }

        /// Extract the high 48 bits.
        pub fn getHigh(self: V2) u48 {
            return self.getNative("high");
        }

        /// Format for std.fmt (delegates to toString).
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

    /// Version 3: MD5 hash-based UUID.
    /// Deterministic based on namespace UUID + name.
    ///
    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-3
    pub const V3 = packed struct(u128) {
        /// The low 62 bits of the MD5 hash.
        md5_low: u62,
        /// The 2-bit variant field (should be 0b10).
        variant: u2,
        /// The middle 12 bits of the MD5 hash.
        md5_mid: u12,
        /// The 4-bit version field (should be 3).
        version: u4,
        /// The high 48 bits of the MD5 hash.
        md5_high: u48,

        /// Create a V3 UUID from a namespace UUID and name.
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

        /// Convert to the generic Uuid union type.
        pub fn toUuid(self: V3) Uuid {
            return .{ .v3 = self };
        }

        /// Convert to a big-endian byte array.
        pub fn toBytes(self: V3) [16]u8 {
            return @bitCast(self);
        }

        /// Convert to a native-endian u128.
        pub fn toNative(self: V3) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        /// Convert to a big-endian u128.
        pub fn toBig(self: V3) u128 {
            return @bitCast(self);
        }

        /// Convert to a little-endian u128.
        pub fn toLittle(self: V3) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        /// Format as the standard UUID string.
        pub fn toString(self: V3) [36]u8 {
            return self.toUuid().toString();
        }

        /// Get a pointer to the underlying bytes.
        pub fn asBytes(self: *const V3) *const [16]u8 {
            return @ptrCast(self);
        }

        /// Get a slice view of the underlying bytes.
        pub fn asSlice(self: V3) []const u8 {
            return self.asBytes();
        }

        /// Test equality with another V3 UUID.
        pub fn eql(self: V3, other: V3) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        /// Compare ordering with another V3 UUID.
        pub fn order(self: V3, other: V3) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        /// Extract the variant field.
        pub fn getVariant(self: V3) Variant {
            return self.toUuid().getVariant();
        }

        /// Extract the version field.
        pub fn getVersion(self: V3) Version {
            return self.toUuid().getVersion().?;
        }

        /// Extract the 122 bits of MD5 hash data.
        pub fn getMd5(self: V3) u122 {
            const low = self.getNative("md5_low");
            const mid = self.getNative("md5_mid");
            const high = self.getNative("md5_high");

            return (@as(u122, high) << 74) | (@as(u122, mid) << 62) | low;
        }

        /// Format for std.fmt (delegates to toString).
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

    /// Version 4: Random UUID.
    /// Contains 122 bits of randomness, most commonly used.
    ///
    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-4
    pub const V4 = packed struct(u128) {
        /// The low 62 bits of random data.
        random_c: u62,
        /// The 2-bit variant field (should be 0b10).
        variant: u2,
        /// The middle 12 bits of random data.
        random_b: u12,
        /// The 4-bit version field (should be 4).
        version: u4,
        /// The high 48 bits of random data.
        random_a: u48,

        /// Create a V4 UUID with cryptographic random data.
        pub fn init(rand: Random) V4 {
            var self: V4 = undefined;

            writeField(V4, "random_c", &self, rand.int(u62));
            writeField(V4, "variant", &self, 0b10);
            writeField(V4, "random_b", &self, rand.int(u12));
            writeField(V4, "version", &self, 4);
            writeField(V4, "random_a", &self, rand.int(u48));

            return self;
        }

        /// Convert to the generic Uuid union type.
        pub fn toUuid(self: V4) Uuid {
            return .{ .v4 = self };
        }

        /// Convert to a big-endian byte array.
        pub fn toBytes(self: V4) [16]u8 {
            return @bitCast(self);
        }

        /// Convert to a native-endian u128.
        pub fn toNative(self: V4) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        /// Convert to a big-endian u128.
        pub fn toBig(self: V4) u128 {
            return @bitCast(self);
        }

        /// Convert to a little-endian u128.
        pub fn toLittle(self: V4) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        /// Format as the standard UUID string.
        pub fn toString(self: V4) [36]u8 {
            return self.toUuid().toString();
        }

        /// Get a pointer to the underlying bytes.
        pub fn asBytes(self: *const V4) *const [16]u8 {
            return @ptrCast(self);
        }

        /// Get a slice view of the underlying bytes.
        pub fn asSlice(self: V4) []const u8 {
            return self.asBytes();
        }

        /// Test equality with another V4 UUID.
        pub fn eql(self: V4, other: V4) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        /// Compare ordering with another V4 UUID.
        pub fn order(self: V4, other: V4) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        /// Extract the variant field.
        pub fn getVariant(self: V4) Variant {
            return self.toUuid().getVariant();
        }

        /// Extract the version field.
        pub fn getVersion(self: V4) Version {
            return self.toUuid().getVersion().?;
        }

        /// Extract the 122 bits of random data.
        pub fn getRandom(self: V4) u122 {
            const c = self.getNative("random_c");
            const b = self.getNative("random_b");
            const a = self.getNative("random_a");

            return (@as(u122, a) << 74) | (@as(u122, b) << 62) | c;
        }

        /// Format for std.fmt (delegates to toString).
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

    /// Version 5: SHA-1 hash-based UUID.
    /// Deterministic based on namespace UUID + name, preferred over V3.
    ///
    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-5
    pub const V5 = packed struct(u128) {
        /// The low 62 bits of the SHA-1 hash.
        sha1_low: u62,
        /// The 2-bit variant field (should be 0b10).
        variant: u2,
        /// The middle 12 bits of the SHA-1 hash.
        sha1_mid: u12,
        /// The 4-bit version field (should be 5).
        version: u4,
        /// The high 48 bits of the SHA-1 hash.
        sha1_high: u48,

        /// Create a V5 UUID from a namespace UUID and name.
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

        /// Convert to the generic Uuid union type.
        pub fn toUuid(self: V5) Uuid {
            return .{ .v5 = self };
        }

        /// Convert to a big-endian byte array.
        pub fn toBytes(self: V5) [16]u8 {
            return @bitCast(self);
        }

        /// Convert to a native-endian u128.
        pub fn toNative(self: V5) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        /// Convert to a big-endian u128.
        pub fn toBig(self: V5) u128 {
            return @bitCast(self);
        }

        /// Convert to a little-endian u128.
        pub fn toLittle(self: V5) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        /// Format as the standard UUID string.
        pub fn toString(self: V5) [36]u8 {
            return self.toUuid().toString();
        }

        /// Get a pointer to the underlying bytes.
        pub fn asBytes(self: *const V5) *const [16]u8 {
            return @ptrCast(self);
        }

        /// Get a slice view of the underlying bytes.
        pub fn asSlice(self: V5) []const u8 {
            return self.asBytes();
        }

        /// Test equality with another V5 UUID.
        pub fn eql(self: V5, other: V5) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        /// Compare ordering with another V5 UUID.
        pub fn order(self: V5, other: V5) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        /// Extract the variant field.
        pub fn getVariant(self: V5) Variant {
            return self.toUuid().getVariant();
        }

        /// Extract the version field.
        pub fn getVersion(self: V5) Version {
            return self.toUuid().getVersion().?;
        }

        /// Extract the 122 bits of SHA-1 hash data.
        pub fn getSha1(self: V5) u122 {
            const low = self.getNative("sha1_low");
            const mid = self.getNative("sha1_mid");
            const high = self.getNative("sha1_high");

            return (@as(u122, high) << 74) | (@as(u122, mid) << 62) | low;
        }

        /// Format for std.fmt (delegates to toString)
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

    /// Version 6: Reordered time + node ID.
    /// Time-ordered like V1 but with better sorting properties.
    ///
    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-6
    pub const V6 = packed struct(u128) {
        /// The 48-bit node ID (typically a MAC address).
        node: u48,
        /// The 14-bit clock sequence for collision avoidance.
        clock_seq: u14,
        /// The 2-bit variant field (should be 0b10).
        variant: u2,
        /// The low 12 bits of the 60-bit timestamp.
        time_low: u12,
        /// The 4-bit version field (should be 6).
        version: u4,
        /// The middle 16 bits of the 60-bit timestamp.
        time_mid: u16,
        /// The high 32 bits of the 60-bit timestamp.
        time_high: u32,

        /// The timestamp structure for V6 UUIDs.
        pub const Timestamp = struct {
            /// The number of nanoseconds per tick (100ns intervals since 1582-10-15).
            pub const ns_per_tick = 100;
            /// The nanosecond offset from the Gregorian epoch to the Unix epoch.
            pub const ns_unix_offset = greg_unix_offset * ns_per_tick;
            /// The 60-bit timestamp in 100ns ticks since 1582-10-15.
            tick: u60,
            /// The 14-bit clock sequence.
            seq: u14,

            /// Get the current timestamp with thread-safe clock sequence.
            pub fn safe() Timestamp {
                return SafeClockSequence(Timestamp).System.next();
            }

            /// Get the current timestamp with singled-threaded sequential clock sequence.
            pub fn fast() Timestamp {
                return FastClockSequence(Timestamp).System.next();
            }
        };

        /// Create a V6 UUID from a timestamp and node ID.
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

        /// Create a V6 UUID with the current timestamp and node ID.
        pub fn now(node: u48) V6 {
            return .init(.safe(), node);
        }

        /// Convert to the generic Uuid union type.
        pub fn toUuid(self: V6) Uuid {
            return .{ .v6 = self };
        }

        /// Convert to a big-endian byte array.
        pub fn toBytes(self: V6) [16]u8 {
            return @bitCast(self);
        }

        /// Convert to a native-endian u128.
        pub fn toNative(self: V6) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        /// Convert to a big-endian u128.
        pub fn toBig(self: V6) u128 {
            return @bitCast(self);
        }

        /// Convert to a little-endian u128.
        pub fn toLittle(self: V6) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        /// Format as the standard UUID string.
        pub fn toString(self: V6) [36]u8 {
            return self.toUuid().toString();
        }

        /// Get a pointer to the underlying bytes.
        pub fn asBytes(self: *const V6) *const [16]u8 {
            return @ptrCast(self);
        }

        /// Get a slice view of the underlying bytes.
        pub fn asSlice(self: V6) []const u8 {
            return self.asBytes();
        }

        /// Test equality with another V6 UUID.
        pub fn eql(self: V6, other: V6) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        /// Compare ordering with another V6 UUID.
        pub fn order(self: V6, other: V6) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        /// Extract the node ID field.
        pub fn getNode(self: V6) u48 {
            return self.getNative("node");
        }

        /// Extract the clock sequence field.
        pub fn getClockSeq(self: V6) u14 {
            return self.getNative("clock_seq");
        }

        /// Extract the variant field.
        pub fn getVariant(self: V6) Variant {
            return self.toUuid().getVariant();
        }

        /// Extract the version field.
        pub fn getVersion(self: V6) Version {
            return self.toUuid().getVersion().?;
        }

        /// Extract the 60-bit timestamp field.
        pub fn getTime(self: V6) u60 {
            const low = self.getNative("time_low");
            const mid = self.getNative("time_mid");
            const high = self.getNative("time_high");

            return (@as(u60, high) << 28) | (@as(u60, mid) << 12) | low;
        }

        /// Format for std.fmt (delegates to toString)
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

    /// Version 7: Unix timestamp + random data.
    /// Time-ordered with millisecond precision, good default choice.
    ///
    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-7
    pub const V7 = packed struct(u128) {
        /// The low 62 bits of random data.
        rand_b: u62,
        /// The 2-bit variant field (should be 0b10).
        variant: u2,
        /// The high 12 bits of random data.
        rand_a: u12,
        /// The 4-bit version field (should be 7).
        version: u4,
        /// The 48-bit Unix timestamp in milliseconds.
        unix_ts_ms: u48,

        /// The timestamp structure for V7 UUIDs.
        pub const Timestamp = struct {
            /// The number of nanoseconds per tick (1ms intervals).
            pub const ns_per_tick = std.time.ns_per_ms;
            /// The nanosecond offset from the Unix epoch (none needed).
            pub const ns_unix_offset = 0;
            /// The 48-bit timestamp in milliseconds since the Unix epoch.
            tick: u48,
            /// The 74-bit sequence for collision avoidance.
            seq: u74,

            /// Get the current timestamp with thread-safe clock sequence.
            pub fn safe() Timestamp {
                return SafeClockSequence(Timestamp).System.next();
            }

            /// Get the current timestamp with singled-threaded sequential clock sequence.
            pub fn fast() Timestamp {
                return FastClockSequence(Timestamp).System.next();
            }
        };

        /// Create a V7 UUID from a timestamp.
        pub fn init(ts: Timestamp) V7 {
            var self: V7 = undefined;

            writeField(V7, "rand_b", &self, @as(u62, @truncate(ts.seq)));
            writeField(V7, "variant", &self, 0b10);
            writeField(V7, "rand_a", &self, @as(u12, @truncate(ts.seq >> 62)));
            writeField(V7, "version", &self, 7);
            writeField(V7, "unix_ts_ms", &self, ts.tick);

            return self;
        }

        /// Create a V7 UUID with the current timestamp.
        pub fn now() V7 {
            return .init(.safe());
        }

        /// Convert to the generic Uuid union type.
        pub fn toUuid(self: V7) Uuid {
            return .{ .v7 = self };
        }

        /// Convert to a big-endian byte array.
        pub fn toBytes(self: V7) [16]u8 {
            return @bitCast(self);
        }

        /// Convert to a native-endian u128.
        pub fn toNative(self: V7) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        /// Convert to a big-endian u128.
        pub fn toBig(self: V7) u128 {
            return @bitCast(self);
        }

        /// Convert to a little-endian u128.
        pub fn toLittle(self: V7) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        /// Get a pointer to the underlying bytes.
        pub fn asBytes(self: *const V7) *const [16]u8 {
            return @ptrCast(self);
        }

        /// Get a slice view of the underlying bytes.
        pub fn asSlice(self: V7) []const u8 {
            return self.asBytes();
        }

        /// Format as the standard UUID string.
        pub fn toString(self: V7) [36]u8 {
            return self.toUuid().toString();
        }

        /// Test equality with another V7 UUID.
        pub fn eql(self: V7, other: V7) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        /// Compare ordering with another V7 UUID.
        pub fn order(self: V7, other: V7) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        /// Extract the Unix timestamp in milliseconds.
        pub fn getUnixMs(self: V7) u48 {
            return self.getNative("unix_ts_ms");
        }

        /// Extract the variant field.
        pub fn getVariant(self: V7) Variant {
            return self.toUuid().getVariant();
        }

        /// Extract the version field.
        pub fn getVersion(self: V7) Version {
            return self.toUuid().getVersion().?;
        }

        /// Extract the 74 bits of random data.
        pub fn getRand(self: V7) u74 {
            const b = self.getNative("rand_b");
            const a = self.getNative("rand_a");

            return (@as(u74, a) << 62) | b;
        }

        /// Format for std.fmt (delegates to toString)
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

    /// Version 8: Custom/experimental UUID.
    /// Application-defined format, experimental use only.
    ///
    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-8
    pub const V8 = packed struct(u128) {
        /// The low 62 bits of custom data.
        custom_c: u62,
        /// The 2-bit variant field (should be 0b10).
        variant: u2,
        /// The middle 12 bits of custom data.
        custom_b: u12,
        /// The 4-bit version field (should be 8).
        version: u4,
        /// The high 48 bits of custom data.
        custom_a: u48,

        /// Create a V8 UUID from 122 bits of custom data.
        pub fn init(custom: u122) V8 {
            var self: V8 = undefined;

            writeField(V8, "custom_c", &self, @as(u62, @truncate(custom)));
            writeField(V8, "variant", &self, 0b10);
            writeField(V8, "custom_b", &self, @as(u12, @truncate(custom >> 62)));
            writeField(V8, "version", &self, 8);
            writeField(V8, "custom_a", &self, @as(u48, @truncate(custom >> 74)));

            return self;
        }

        /// Convert to the generic Uuid union type.
        pub fn toUuid(self: V8) Uuid {
            return .{ .v8 = self };
        }

        /// Convert to a big-endian byte array.
        pub fn toBytes(self: V8) [16]u8 {
            return @bitCast(self);
        }

        /// Convert to a native-endian u128.
        pub fn toNative(self: V8) u128 {
            return switch (native_endian) {
                .little => self.toLittle(),
                .big => self.toBig(),
            };
        }

        /// Convert to a big-endian u128.
        pub fn toBig(self: V8) u128 {
            return @bitCast(self);
        }

        /// Convert to a little-endian u128.
        pub fn toLittle(self: V8) u128 {
            return @byteSwap(@as(u128, @bitCast(self)));
        }

        /// Format as the standard UUID string.
        pub fn toString(self: V8) [36]u8 {
            return self.toUuid().toString();
        }

        /// Get a pointer to the underlying bytes.
        pub fn asBytes(self: *const V8) *const [16]u8 {
            return @ptrCast(self);
        }

        /// Get a slice view of the underlying bytes.
        pub fn asSlice(self: V8) []const u8 {
            return self.asBytes();
        }

        /// Test equality with another V8 UUID.
        pub fn eql(self: V8, other: V8) bool {
            return std.mem.eql(u8, self.asBytes(), other.asBytes());
        }

        /// Compare ordering with another V8 UUID.
        pub fn order(self: V8, other: V8) std.math.Order {
            return std.mem.order(u8, self.asBytes(), other.asBytes());
        }

        /// Extract the variant field.
        pub fn getVariant(self: V8) Variant {
            return self.toUuid().getVariant();
        }

        /// Extract the version field.
        pub fn getVersion(self: V8) Version {
            return self.toUuid().getVersion().?;
        }

        /// Extract the 122 bits of custom data.
        pub fn getCustom(self: V8) u122 {
            const c = self.getNative("custom_c");
            const b = self.getNative("custom_b");
            const a = self.getNative("custom_a");

            return (@as(u122, a) << 74) | (@as(u122, b) << 62) | c;
        }

        /// Format for std.fmt (delegates to toString)
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

    /// Format for std.fmt (delegates to toString)
    pub fn format(
        self: Uuid,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const string = self.toString();
        try writer.writeAll(&string);
    }

    /// A clock abstraction for timestamp generation in time-based UUIDs.
    pub const Clock = struct {
        ptr: *anyopaque,
        nanoTimestampFn: *const fn (ptr: *anyopaque) i128,

        pub const system = Clock.init(&.{}, systemClock);
        pub const zero = Clock.init(&.{}, zeroClock);

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

    /// A single-threaded clock sequence generator for time-based UUIDs.
    ///
    /// It does not use a random number generator. Sequences are incremented sequentially until
    /// they reach the maximum value, at which point it starts accumulating "debt" by moving time
    /// forward. The debt is paid off as time passes; but this creates a situation where the timestamp
    /// is not accurate, for the sake of raw throughput.
    ///
    /// This is not thread-safe, not well distributed, and not 100% compliant with the UUID specification,
    /// however it is fast and still monotonic when used in a single-threaded environment.
    pub fn FastClockSequence(comptime Timestamp: type) type {
        return struct {
            pub const Tick = @FieldType(Timestamp, "tick");
            pub const Seq = @FieldType(Timestamp, "seq");

            pub var System: @This() = .{
                .clock = .system,
            };

            pub const Zero: @This() = .{
                .clock = .zero,
            };

            clock: Clock,
            last_tick: Tick = 0,
            acc: Tick = 0,
            seq: Seq = 0,

            pub fn next(self: *@This()) Timestamp {
                const actual_tick = self.tickTimestamp();

                const delta = actual_tick -| self.last_tick;
                self.acc -|= delta;

                const acc_tick = self.last_tick + self.acc;
                const acc_seq = self.seq;

                if (actual_tick > acc_tick) {
                    self.last_tick = actual_tick;
                    self.acc = 0;
                    self.seq = 0;
                } else {
                    const result = @addWithOverflow(self.seq, 1);
                    if (result[1] == 1) {
                        self.acc += 1;
                        self.seq = 0;
                    } else {
                        self.seq = result[0];
                    }
                }

                return .{
                    .tick = acc_tick,
                    .seq = acc_seq,
                };
            }

            fn tickTimestamp(self: *@This()) Tick {
                const ns = self.clock.nanoTimestamp() + Timestamp.ns_unix_offset;
                return @intCast(@divFloor(ns, Timestamp.ns_per_tick));
            }
        };
    }

    /// A thread-safe clock sequence generator using atomic operations.
    /// This is suitable for concurrent UUID generation across multiple threads.
    pub fn SafeClockSequence(comptime Timestamp: type) type {
        return struct {
            pub const Tick = @FieldType(Timestamp, "tick");
            pub const Seq = @FieldType(Timestamp, "seq");

            pub const State = packed struct(u128) {
                last: Tick = 0,
                _: std.meta.Int(.unsigned, 128 - @bitSizeOf(Tick) - @bitSizeOf(Seq)) = 0,
                seq: Seq = 0,
            };

            comptime {
                if (@bitSizeOf(Tick) + @bitSizeOf(Seq) > 128) {
                    @compileError("Tick + Seq cannot exceed 128 bits");
                }
            }

            pub var System: @This() = .{
                .clock = .system,
            };

            pub const Zero: @This() = .{
                .clock = .zero,
            };

            clock: Clock,
            rand: Random = std.crypto.random,
            state: std.atomic.Value(State) = .init(.{}),

            pub fn next(self: *@This()) Timestamp {
                var new: State = .{};
                var prng = std.Random.DefaultPrng.init(self.rand.int(u64));

                while (true) {
                    const tick = self.tickTimestamp();
                    const old = self.state.load(.acquire);
                    const max_step = @min(std.math.maxInt(Seq), std.math.maxInt(u16));

                    if (tick > old.last) {
                        new.last = tick;
                        new.seq = self.rand.int(Seq);
                    } else {
                        const result = @addWithOverflow(old.seq, prng.random().uintAtMost(Seq, max_step));
                        if (result[1] != 0) {
                            continue;
                        }
                        new.last = old.last;
                        new.seq = result[0];
                    }

                    if (self.state.cmpxchgWeak(old, new, .release, .acquire)) |_| {
                        continue;
                    } else {
                        return .{
                            .tick = new.last,
                            .seq = new.seq,
                        };
                    }
                }
            }

            fn tickTimestamp(self: *@This()) Tick {
                const ns = self.clock.nanoTimestamp() + Timestamp.ns_unix_offset;
                return @intCast(@divFloor(ns, Timestamp.ns_per_tick));
            }
        };
    }
};

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

const test_allocator = std.testing.allocator;

test "RFC9562 Test Vector A.1" {
    const uuid = try Uuid.parse("c232ab00-9414-11ec-b3c8-9f6bdeced846");
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
    const ns = try Uuid.parse("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
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
    const uuid = try Uuid.parse("919108f7-52d1-4320-9bac-f847db4148a8");
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
    const ns = try Uuid.parse("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
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
    const uuid = try Uuid.parse("1ec9414c-232a-6b00-b3c8-9f6bdeced846");
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
    const uuid = try Uuid.parse("017f22e2-79b0-7cc3-98c4-dc0c0c07398f");
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
    const uuid = try Uuid.parse("2489e9ad-2ee2-8e00-8ec9-32d5f69181c0");
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
    const uuid = try Uuid.parse("5c146b14-3c52-8afd-938a-375d0df1fbf6");
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
    const nil1 = Uuid.nil;
    const nil2 = Uuid.fromNative(0);

    try std.testing.expect(nil1.eql(nil2));
    try std.testing.expect(nil1.isNil());
    try std.testing.expect(!nil1.isMax());
    try std.testing.expectEqual(.nil, nil1.getVersion());

    // Test max UUID
    const max1 = Uuid.max;
    const max2 = Uuid.fromNative(std.math.maxInt(u128));

    try std.testing.expect(max1.eql(max2));
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
            Uuid.V3 => V.init(.dns, "test"),
            Uuid.V4 => V.init(std.crypto.random),
            Uuid.V5 => V.init(.dns, "test"),
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

test "v7 ordering" {
    var seq = Uuid.SafeClockSequence(Uuid.V7.Timestamp).Zero;

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

    const v3_1 = Uuid.V3.init(.dns, name);
    const v3_2 = Uuid.V3.init(.dns, name);
    const v5_1 = Uuid.V5.init(.dns, name);
    const v5_2 = Uuid.V5.init(.dns, name);

    try std.testing.expect(v3_1.eql(v3_2));
    try std.testing.expect(v5_1.eql(v5_2));
    try std.testing.expect(!v3_1.toUuid().eql(v5_1.toUuid())); // Different algorithms
}

test "v3 v5 namespace sensitivity" {
    const name = "example.com";

    const v3_dns = Uuid.V3.init(.dns, name);
    const v3_url = Uuid.V3.init(.url, name);
    const v5_dns = Uuid.V5.init(.dns, name);
    const v5_url = Uuid.V5.init(.url, name);

    try std.testing.expect(!v3_dns.eql(v3_url));
    try std.testing.expect(!v5_dns.eql(v5_url));
}

test "v4 randomness" {
    // Test that V4 UUIDs are unique across a reasonable sample
    var seen = std.AutoHashMap([16]u8, void).init(test_allocator);
    defer seen.deinit();

    for (0..10_000) |_| {
        const uuid = Uuid.V4.init(std.crypto.random);
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
    const v1_ts = Uuid.V1.Timestamp.fast();
    const v1 = Uuid.V1.init(v1_ts, node);
    try std.testing.expectEqual(.v1, v1.getVersion());
    try std.testing.expectEqual(.rfc9562, v1.getVariant());
    try std.testing.expectEqual(node, v1.getNode());

    // V3 with namespace and name
    const v3 = Uuid.V3.init(.dns, "example.com");
    try std.testing.expectEqual(.v3, v3.getVersion());
    try std.testing.expectEqual(.rfc9562, v3.getVariant());

    // V4 random
    const v4 = Uuid.V4.init(std.crypto.random);
    try std.testing.expectEqual(.v4, v4.getVersion());
    try std.testing.expectEqual(.rfc9562, v4.getVariant());

    // V5 with namespace and name
    const v5 = Uuid.V5.init(.url, "https://example.com");
    try std.testing.expectEqual(.v5, v5.getVersion());
    try std.testing.expectEqual(.rfc9562, v5.getVariant());

    // V6 with timestamp and node
    const v6_ts = Uuid.V6.Timestamp.fast();
    const v6 = Uuid.V6.init(v6_ts, node);
    try std.testing.expectEqual(.v6, v6.getVersion());
    try std.testing.expectEqual(.rfc9562, v6.getVariant());
    try std.testing.expectEqual(node, v6.getNode());

    // V7 with timestamp
    const v7_ts = Uuid.V7.Timestamp.fast();
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
    const dns_formatted = try std.fmt.allocPrint(test_allocator, "{}", .{Uuid.dns});
    defer test_allocator.free(dns_formatted);
    try std.testing.expectEqualStrings("6ba7b810-9dad-11d1-80b4-00c04fd430c8", dns_formatted);

    const url_formatted = try std.fmt.allocPrint(test_allocator, "{}", .{Uuid.url});
    defer test_allocator.free(url_formatted);
    try std.testing.expectEqualStrings("6ba7b811-9dad-11d1-80b4-00c04fd430c8", url_formatted);

    // Test that all namespaces are different
    try std.testing.expect(!Uuid.dns.eql(.url));
    try std.testing.expect(!Uuid.dns.eql(.oid));
    try std.testing.expect(!Uuid.dns.eql(.x500));
    try std.testing.expect(!Uuid.url.eql(.oid));
    try std.testing.expect(!Uuid.url.eql(.x500));
    try std.testing.expect(!Uuid.oid.eql(.x500));
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
    try std.testing.expectEqual(.lt, Uuid.nil.order(uuid_low));
    try std.testing.expectEqual(.gt, Uuid.max.order(uuid_high));
}

test "clock sequence randomization" {
    // Test that SafeClockSequence uses randomization for sequence values
    var seq = Uuid.SafeClockSequence(Uuid.V7.Timestamp).System;

    // Generate multiple timestamps and check for sequence variation
    var timestamps: [10]Uuid.V7.Timestamp = undefined;
    for (&timestamps) |*ts| {
        ts.* = seq.next();
    }

    // SafeClockSequence should produce different sequence values due to randomization
    var has_different_sequences = false;
    for (timestamps[0 .. timestamps.len - 1], timestamps[1..]) |curr, next| {
        if (curr.seq != next.seq) {
            has_different_sequences = true;
            break;
        }
    }

    // All timestamps should be valid
    for (timestamps) |ts| {
        try std.testing.expect(ts.tick >= 0);
        try std.testing.expect(ts.seq >= 0);
    }

    // With randomization, we should see some sequence variation
    try std.testing.expect(has_different_sequences);
}

test "fast clock accumulation" {
    var seq = Uuid.FastClockSequence(struct {
        pub const ns_per_tick = 1;
        pub const ns_unix_offset = 0;
        tick: u8,
        seq: u1,
    }).Zero;

    try std.testing.expectEqual(0, seq.last_tick);
    try std.testing.expectEqual(0, seq.acc);
    try std.testing.expectEqual(0, seq.seq);
    var ts = seq.next();
    try std.testing.expectEqual(0, ts.tick);
    try std.testing.expectEqual(0, ts.seq);

    try std.testing.expectEqual(0, seq.last_tick);
    try std.testing.expectEqual(0, seq.acc);
    try std.testing.expectEqual(1, seq.seq);
    ts = seq.next();
    try std.testing.expectEqual(0, ts.tick);
    try std.testing.expectEqual(1, ts.seq);

    try std.testing.expectEqual(0, seq.last_tick);
    try std.testing.expectEqual(1, seq.acc);
    try std.testing.expectEqual(0, seq.seq);
    ts = seq.next();
    try std.testing.expectEqual(1, ts.tick);
    try std.testing.expectEqual(0, ts.seq);

    try std.testing.expectEqual(0, seq.last_tick);
    try std.testing.expectEqual(1, seq.acc);
    try std.testing.expectEqual(1, seq.seq);
    ts = seq.next();
    try std.testing.expectEqual(1, ts.tick);
    try std.testing.expectEqual(1, ts.seq);

    try std.testing.expectEqual(0, seq.last_tick);
    try std.testing.expectEqual(2, seq.acc);
    try std.testing.expectEqual(0, seq.seq);
    ts = seq.next();
    try std.testing.expectEqual(2, ts.tick);
    try std.testing.expectEqual(0, ts.seq);
}

test "single-threaded clock sequence deterministic behavior" {
    // Test FastClockSequence deterministic sequence increments
    var seq = Uuid.FastClockSequence(Uuid.V7.Timestamp).Zero;

    // Generate a small number of timestamps to test basic increment behavior
    const ts1 = seq.next();
    const ts2 = seq.next();
    const ts3 = seq.next();

    // For zero clock, all timestamps should have the same tick
    try std.testing.expectEqual(ts1.tick, ts2.tick);
    try std.testing.expectEqual(ts2.tick, ts3.tick);

    // FastClockSequence should increment sequence deterministically
    try std.testing.expectEqual(ts1.seq + 1, ts2.seq);
    try std.testing.expectEqual(ts2.seq + 1, ts3.seq);

    // Test that sequence starts from 0 for Zero clock
    var fresh_seq = Uuid.FastClockSequence(Uuid.V7.Timestamp).Zero;
    const first_ts = fresh_seq.next();
    try std.testing.expectEqual(0, first_ts.seq);
}

test "clock sequence behavior with system clock" {
    // Test that FastClockSequence works correctly with system clock
    var seq = Uuid.FastClockSequence(Uuid.V7.Timestamp).System;

    // Generate a few timestamps
    const ts1 = seq.next();
    const ts2 = seq.next();
    const ts3 = seq.next();

    // All timestamps should be valid
    try std.testing.expect(ts1.tick >= 0);
    try std.testing.expect(ts2.tick >= 0);
    try std.testing.expect(ts3.tick >= 0);
    try std.testing.expect(ts1.seq >= 0);
    try std.testing.expect(ts2.seq >= 0);
    try std.testing.expect(ts3.seq >= 0);

    // Timestamps should be monotonically increasing or have incrementing sequences
    if (ts1.tick == ts2.tick) {
        try std.testing.expect(ts2.seq > ts1.seq);
    } else {
        try std.testing.expect(ts2.tick > ts1.tick);
    }
}

test "clock sequence thread safety" {
    if (builtin.single_threaded) return; // Skip on single-threaded builds

    const ThreadCount = 4; // Reduced for faster testing
    const IterationsPerThread = 100; // Reduced for faster testing

    var seq = Uuid.SafeClockSequence(Uuid.V7.Timestamp).System; // Use System clock for better tick variation
    var threads: [ThreadCount]std.Thread = undefined;
    var results: [ThreadCount][IterationsPerThread]Uuid.V7.Timestamp = undefined;

    const ThreadArgs = struct {
        seq: *Uuid.SafeClockSequence(Uuid.V7.Timestamp),
        results: *[IterationsPerThread]Uuid.V7.Timestamp,
    };

    const worker = struct {
        fn run(args: ThreadArgs) void {
            for (args.results) |*result| {
                result.* = args.seq.next();
            }
        }
    }.run;

    // Spawn threads
    for (&threads, 0..) |*thread, i| {
        const args = ThreadArgs{
            .seq = &seq,
            .results = &results[i],
        };
        thread.* = try std.Thread.spawn(.{}, worker, .{args});
    }

    // Wait for all threads to complete
    for (threads) |thread| {
        thread.join();
    }

    // Collect all timestamps and verify basic properties
    var timestamp_count: usize = 0;
    var has_different_sequences = false;

    for (results) |thread_results| {
        for (thread_results) |timestamp| {
            timestamp_count += 1;
            // Verify timestamp is valid (non-negative values)
            try std.testing.expect(timestamp.tick >= 0);
            try std.testing.expect(timestamp.seq >= 0);
        }
    }

    // Check that we have different sequence numbers (due to randomization)
    outer: for (results) |thread_results| {
        for (thread_results[0 .. thread_results.len - 1], thread_results[1..]) |curr, next| {
            if (curr.seq != next.seq) {
                has_different_sequences = true;
                break :outer;
            }
        }
    }

    // Verify that we got the expected number of timestamps
    try std.testing.expectEqual(ThreadCount * IterationsPerThread, timestamp_count);

    // SafeClockSequence uses randomization, so we should see sequence variation
    try std.testing.expect(has_different_sequences);
}

test "format edge cases" {
    // Test formatting with all zeros and all ones
    const all_zeros = Uuid.nil;
    const zeros_str = try std.fmt.allocPrint(test_allocator, "{}", .{all_zeros});
    defer test_allocator.free(zeros_str);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000000", zeros_str);

    const all_ones = Uuid.max;
    const ones_str = try std.fmt.allocPrint(test_allocator, "{}", .{all_ones});
    defer test_allocator.free(ones_str);
    try std.testing.expectEqualStrings("ffffffff-ffff-ffff-ffff-ffffffffffff", ones_str);

    // Test that format length is always consistent
    for (0..100) |_| {
        const random_uuid = Uuid.V4.init(std.crypto.random);
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
