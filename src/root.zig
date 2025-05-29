const std = @import("std");

const Allocator = std.mem.Allocator;
const Random = std.rand.Random;
const Md5 = std.crypto.hash.Md5;
const Sha1 = std.crypto.hash.Sha1;

const rand = std.crypto.random;

const ms_per_s = std.time.ms_per_s;
const ns_per_s = std.time.ns_per_s;
const ns_per_ms = std.time.ns_per_ms;
const ns_per_tick = 100;
const tick_per_s = std.time.ns_per_s / ns_per_tick;

const ticks_between_epochs: u64 = 0x01B2_1DD2_1381_4000;

pub const Uuid = packed union {
    v1: V1,
    v3: V3,
    v4: V4,
    v5: V5,
    v6: V6,
    v7: V7,
    v8: V8,

    nil: Nil,
    max: Max,

    pub const Nil = packed struct(u128) { bits: u128 };
    pub const Max = packed struct(u128) { bits: u128 };

    pub const NIL = Uuid.Nil{ .bits = 0x00000000_0000_0000_0000_000000000000 };
    pub const MAX = Uuid.Max{ .bits = 0xFFFFFFFF_FFFF_FFFF_FFFF_FFFFFFFFFFFF };

    pub fn version(self: Uuid) Version {
        const bytes = @as([16]u8, @bitCast(self));
        return @enumFromInt(@as(u4, @truncate((bytes[6] >> 4) & 0xF)));
    }

    pub fn variant(self: Uuid) Variant {
        const bytes = @as([16]u8, @bitCast(self));
        return @enumFromInt(@as(u2, @truncate((bytes[8] >> 6) & 0x3)));
    }

    pub const Version = enum(u4) {
        nil = 0b0000,
        mac = 1,
        dce = 2,
        md5 = 3,
        random = 4,
        sha1 = 5,
        sort_mac = 6,
        sort_rand = 7,
        custom = 8,
        max = 0b1111,
        _,
    };

    pub const Variant = enum(u2) {
        nil = 0,
        rfc4122 = 1,
        microsoft = 2,
        reserved = 3,
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-1
    pub const V1 = packed struct(u128) {
        time_low: u32,
        time_mid: u16,
        version: u4 = 1,
        time_high: u12,
        variant: u2 = 0b10,
        clock_seq: u14,
        node: u48,

        pub fn init(ts: Timestamp, node: u48) V1 {
            const gregorian = ts.toV1();

            return V1{
                .time_low = @truncate(gregorian.ticks),
                .time_mid = @truncate(gregorian.ticks >> 32),
                .time_high = @truncate(gregorian.ticks >> 48),
                .clock_seq = gregorian.counter,
                .node = node,
            };
        }
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-3
    pub const V3 = packed struct(u128) {
        md5_high: u48,
        version: u4 = 3,
        md5_mid: u12,
        variant: u2 = 0b10,
        md5_low: u62,

        pub fn init(namespace: Uuid, name: []const u8) V3 {
            var hash: [16]u8 = undefined;

            var hasher = Md5.init(.{});
            hasher.update(std.mem.asBytes(&namespace));
            hasher.update(name);
            hasher.final(&hash);

            const md5 = std.mem.readInt(u128, &hash, .big);

            return V3{
                .md5_high = @truncate(md5 >> 80),
                .md5_mid = @truncate(md5 >> 68),
                .md5_low = @truncate(md5),
            };
        }
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-4
    pub const V4 = packed struct(u128) {
        random_a: u48,
        version: u4 = 4,
        random_b: u12,
        variant: u2 = 0b10,
        random_c: u62,

        pub fn init() V4 {
            return V4{
                .random_a = rand.int(u48),
                .random_b = rand.int(u12),
                .random_c = rand.int(u62),
            };
        }
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-5
    pub const V5 = packed struct(u128) {
        sha1_high: u48,
        version: u4 = 5,
        sha1_mid: u12,
        variant: u2 = 0b10,
        sha1_low: u62,

        pub fn init(namespace: Uuid, name: []const u8) V5 {
            var hash: [20]u8 = undefined;

            var hasher = Sha1.init(.{});
            hasher.update(std.mem.asBytes(&namespace));
            hasher.update(name);
            hasher.final(&hash);

            const sha1 = std.mem.readInt(u128, hash[0..16], .big);

            return V5{
                .sha1_high = @truncate(sha1 >> 80),
                .sha1_mid = @truncate(sha1 >> 68),
                .sha1_low = @truncate(sha1),
            };
        }
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-6
    pub const V6 = packed struct(u128) {
        time_high: u32,
        time_mid: u16,
        version: u4 = 6,
        time_low: u12,
        variant: u2 = 0b10,
        clock_seq: u14,
        node: u48,

        pub fn init(ts: Timestamp, node: u48) V6 {
            const gregorian = ts.toV1();

            return V6{
                .time_high = @truncate(gregorian.ticks >> 28),
                .time_mid = @truncate(gregorian.ticks >> 12),
                .time_low = @truncate(gregorian.ticks),
                .clock_seq = gregorian.counter,
                .node = node,
            };
        }
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-7
    pub const V7 = packed struct(u128) {
        unix_ts_ms: u48,
        version: u4 = 7,
        rand_a: u12,
        variant: u2 = 0b10,
        rand_b: u62,

        pub fn init(ts: Timestamp) V7 {
            const unix = ts.getMillisCounter(48, 42);

            return V7{
                .unix_ts_ms = unix.millis,
                .rand_a = @truncate(unix.counter >> 50),
                .rand_b = @as(u62, @truncate(unix.counter << 12)) | rand.int(u12),
            };
        }
    };

    /// https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-8
    pub const V8 = packed struct(u128) {
        custom_a: u48,
        version: u4 = 8,
        custom_b: u12,
        variant: u2 = 0b10,
        custom_c: u62,

        pub fn init(custom: u122) V8 {
            return V8{
                .custom_a = @truncate(custom >> 74),
                .custom_b = @truncate(custom >> 62),
                .custom_c = @truncate(custom),
            };
        }
    };
};

pub const Timestamp = struct {
    seconds: u64,
    subsec: u32,
    counter: u128,
    usable_bits: u8,

    pub fn fromGregorian(ticks: u64, counter: u128) Timestamp {
        return Timestamp{
            .seconds = ticks / tick_per_s,
            .subsec = (ticks % tick_per_s) * ns_per_tick,
            .counter = @intCast(counter),
        };
    }

    pub fn fromUnix(seconds: u64, subsec: u32, ctx: anytype) Timestamp {
        return Timestamp{
            .seconds = seconds,
            .subsec = subsec,
            .counter = ctx.generateSequence(seconds, subsec),
        };
    }
    pub fn getTicks(comptime width: u8) std.meta.Int(.unsigned, width) {
        @panic("todo");
    }

    pub fn getMillisCounter(comptime millis_width: u8, comptime counter_width: u8) struct {
        millis: std.meta.Int(.unsigned, millis_width),
        counter: std.meta.Int(.unsigned, counter_width),
    } {
        return .{
            .millis = @intCast(self.subsec / ns_per_ms),
            .counter = @intCast(self.counter),
        };
    }
};

pub fn Sequence(comptime width: u8) type {
    return struct {
        const Self = @This();
        const Counter = std.meta.Int(.unsigned, width);
        const Ts = Timestamp(width);

        ptr: *anyopaque,
        vtable: *const VTable,

        const VTable = struct {
            generateSequence: *const fn (ptr: *anyopaque, seconds: u64, subsec: u32) Counter,
            generateTimestampSequence: *const fn (ptr: *anyopaque, seconds: u64, subsec: u32) struct {
                counter: Counter,
                seconds: u64,
                subsec: u32,
            },
        };

        pub fn generateSequence(self: Self, seconds: u64, subsec: u32) Counter {
            return self.vtable.generateSequence(self.ptr, seconds, subsec);
        }

        pub fn generateTimestampSequence(self: Self, seconds: u64, subsec: u32) struct {
            counter: Counter,
            seconds: u64,
            subsec: u32,
        } {
            return self.vtable.generateTimestampSequence(self.ptr, seconds, subsec);
        }

        pub fn now(self: Self) Ts {
            const nanos = std.time.nanoTimestamp();

            const seconds = @as(u64, @intCast(@divFloor(nanos, ns_per_s)));
            const subsec = @as(u32, @intCast(@mod(nanos, ns_per_s)));

            const result = self.generateTimestampSequence(seconds, subsec);

            return Ts.fromUnix(result.seconds, result.subsec, result.counter);
        }
    };
}

pub fn GregorianSequence(comptime width: u8) type {
    if (width > 14) @compileError("Gregorian sequences support maximum 14-bit counters");

    return struct {
        const Self = @This();
        const Counter = std.meta.Int(.unsigned, width);
        const mask = (1 << width) - 1;

        last_ticks: u60 = 0,
        clock_seq: std.atomic.Value(Counter),

        pub fn init() Self {
            return Self{
                .clock_seq = rand.int(Counter),
            };
        }

        pub fn generate(self: *Self, seconds: u64, subsec: u32) struct {
            counter: Counter,
            seconds: u64,
            subsec: u32,
        } {
            self.mutex.lock();
            defer self.mutex.unlock();

            const current_ticks: u60 = @intCast(ticks_between_epochs +
                (seconds * tick_per_s) +
                (subsec / ns_per_tick));

            if (current_ticks <= self.last_ticks) {
                // Clock hasn't advanced or went backward, increment clock sequence
                self.clock_seq = (self.clock_seq +% 1) & mask;
                if (self.clock_seq == 0) {
                    // Overflow occurred, reinitialize
                    self.clock_seq = rand.int(Counter) & mask;
                }
            } else {
                self.last_ticks = current_ticks;
            }

            return .{
                .counter = self.clock_seq,
                .seconds = seconds,
                .subsec = subsec,
            };
        }

        pub fn sequence(self: *Self) Sequence(width) {
            const vtable = &Sequence(width).VTable{
                .generateTimestampSequence = struct {
                    fn call(ptr: *anyopaque, seconds: u64, subsec: u32) struct {
                        counter: Counter,
                        seconds: u64,
                        subsec: u32,
                    } {
                        const seq: *Self = @ptrCast(@alignCast(ptr));
                        return seq.generate(seconds, subsec);
                    }
                }.call,
            };

            return Sequence(width){
                .ptr = self,
                .vtable = vtable,
            };
        }
    };
}

pub fn UnixSequence(comptime width: u8) type {
    if (width < 12) @compileError("Unix sequences need at least 12 bits for sub-millisecond precision");

    return struct {
        const Self = @This();
        const Counter = std.meta.Int(.unsigned, width);
        const max_counter = std.math.maxInt(Counter);

        millis: u48 = 0,
        counter: Counter,

        pub fn init() Self {
            return Self{
                .counter = rand.int(Counter),
            };
        }

        pub fn generate(self: *Self, seconds: u64, subsec: u32) struct {
            seconds: u64,
            subsec: u32,
            counter: Counter,
        } {
            const current_millis: u48 = @intCast(seconds * ms_per_s + subsec / ns_per_ms);

            if (current_millis == self.millis) {
                // Same millisecond, increment counter for monotonicity
                if (self.counter == max_counter) {
                    // Counter overflow, wait for next millisecond or increment timestamp
                    const new_subsec = subsec + ns_per_ms;
                    if (new_subsec >= ns_per_s) {
                        return self.generate(seconds + 1, new_subsec - ns_per_s);
                    } else {
                        return self.generate(seconds, new_subsec);
                    }
                }
                self.counter +%= 1;
            } else if (current_millis > self.millis) {
                // New millisecond, reset counter with sub-millisecond precision
                self.millis = current_millis;

                // Encode sub-millisecond precision in counter
                const submilli_ns = subsec % ns_per_ms;
                const precision_bits = @min(width - 12, 20); // Reserve 12 bits for sequence
                const submilli_fraction = if (precision_bits > 0)
                    (@as(Counter, submilli_ns) << (width - precision_bits)) / ns_per_ms
                else
                    0;

                self.counter = submilli_fraction | (rand.int(Counter) & ((1 << 12) - 1));
            } else {
                // Clock went backward, increment counter significantly
                self.counter +%= 0x1000; // Increment by reasonable amount
                if (self.counter == 0) {
                    self.counter = rand.int(Counter);
                }
            }

            return .{
                .counter = self.counter,
                .seconds = seconds,
                .subsec = subsec,
            };
        }

        pub fn sequence(self: *Self) Sequence(width) {
            const vtable = &Sequence(width).VTable{
                .generateTimestampSequence = struct {
                    fn call(ptr: *anyopaque, seconds: u64, subsec: u32) struct {
                        counter: Counter,
                        seconds: u64,
                        subsec: u32,
                    } {
                        const seq: *Self = @ptrCast(@alignCast(ptr));
                        return seq.generate(seconds, subsec);
                    }
                }.call,
            };

            return Sequence(width){
                .ptr = self,
                .vtable = vtable,
            };
        }
    };
}
