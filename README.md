# uuidz

RFC 9562 compliant UUID implementation for Zig.

## Design

The library is built around a `Uuid` packed union that can represent any UUID format while maintaining type safety. Each UUID version (V1-V8) is implemented as its own packed struct with version-specific fields and methods.

Key design decisions:

- **Packed structs**: All UUID types are `packed struct(u128)` ensuring they're exactly 128 bits
- **Union for flexibility**: The main `Uuid` type is a packed union allowing you to work with any version generically or access version-specific functionality
- **Type safety**: You can use specific types like `Uuid.V4` when you know the version, or the union `Uuid` for generic handling
- **Endianness handling**: Support for big-endian, little-endian, and native byte order conversions
- **Thread safety**: Clock sequences use atomic operations for thread-safe timestamp generation
- **RFC 9562 compliance**: Standard bit field layouts, variant bits, and version bits

The core abstraction separates concerns:

- Clock sequences handle timestamp uniqueness and ordering
- Individual version structs handle format-specific logic
- The union provides a common interface for all versions
- Conversion methods handle different representations (bytes, integers, strings)

This design allows compile-time type safety when you know the UUID version, runtime flexibility when you don't, and efficient representation regardless of how you use it.

The design is heavily influenced by the Rust [uuid](https://github.com/uuid-rs/uuid) crate, with some Zig specific flavoring.

## Installation

Add to `build.zig.zon`:

```zig
.dependencies = .{
    .uuidz = .{
        .url = "https://github.com/user/uuidz/archive/main.tar.gz",
        .hash = "1220...",
    },
},
```

## Usage

```zig
const Uuid = @import("uuidz").Uuid;

// Typed versions to accept only one version
const t1: Uuid.V1 = .now(0x001122334455);
const t3: Uuid.V3 = .init(.dns, "tristanpemble.com");
const t4: Uuid.V4 = .init();
const t5: Uuid.V5 = .init(.dns, "tristanpemble.com");
const t6: Uuid.V6 = .now(0x001122334455);
const t7: Uuid.V7 = .now();
const t8: Uuid.V8 = .init(0x123456789abcdef);

// Union type to accept any version
const u1: Uuid = .{ .v1 = .now(0x001122334455) };
const u3: Uuid = .{ .v3 = .init(.dns, "tristanpemble.com") };
const u4: Uuid = .{ .v4 = .init() };
const u5: Uuid = .{ .v5 = .init(.dns, "tristanpemble.com") };
const u6: Uuid = .{ .v6 = .now(0x001122334455) };
const u7: Uuid = .{ .v7 = .now() };
const u8: Uuid = .{ .v8 = .init(0xC0FFEE_101) };

// Compare
const is_equal: bool = u1.eql(u2);
const order: std.math.Order = u1.order(u2);

// Convert formats
const uuid: Uuid = .fromNative(0x6ba7b810_9dad_11d1_80b4_00c04fd430c8);
const uuid_be: Uuid = .fromBig(0x6ba7b810_9dad_11d1_80b4_00c04fd430c8);
const uuid_le: Uuid = .fromLittle(0x6ba7b810_9dad_11d1_80b4_00c04fd430c8);
const uuid_by: Uuid = .fromBytes(.{ 0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1, 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8 });
const int_ne: u128 = uuid.toNative();
const int_be: u128 = uuid.toBig();
const int_le: u128 = uuid.toLittle();
const bytes: [16]u8 = uuid.toBytes();

// Inspect
const variant: Uuid.Variant = uuid.getVariant();
const version: ?Uuid.Version = uuid.getVersion().?;

const time = switch (version) {
    .v1 => uuid.v1.getTime(),
    .v6 => uuid.v6.getTime(),
    .v7 => uuid.v7.getTime(),
    else => @panic("unhandled uuid version"),
}
```

## Clocks, clock sequences & entropy

For time-based UUIDs (v1, v6, v7), clock sequences ensure uniqueness when multiple UUIDs are generated at the same timestamp. It does
this by using a random initial sequence value that increments for each UUID within the same tick, as per RFC9562.

We provide two ClockSequence implementations, but you are free to write your own:

- `AtomicClockSequence`: The default, a lock-free, thread-safe implementation.
- `LocalClockSequence`: A single-threaded implementation for maximum throughput.

Both implementations accept a `Clock`, so that you can customize their behavior. We provide two clocks:

- `SystemClock`: Uses the system clock to generate timestamps.
- `ZeroClock`: Always returns zero.

They also accept a `std.Random`, allowing you to use a custom random number generator.

For example, to use a single-threaded `LocalClockSequence`, that only outputs zero, with a PRNG, to generate a v7 UUID:

```zig
var rng = std.Random.DefaultPrng.init(0);
var clock_seq = uuidz.LocalClockSequence(uuidz.Uuid.V7.Timestamp){
    .clock = uuidz.Clock.Zero,
    .rand = rng.random(),
};

const uuid: Uuid.V7 = .init(clock_seq.next());
```

### Custom Clocks

You can create and use your own clocks if you need custom behavior for your usecase.

```zig
const FixedClock = struct {
    fixed_time: i128,

    fn nanoTimestamp(self: *FixedClock) i128 {
        return self.fixed_time;
    }

    fn toClock(self: *FixedClock) Clock {
        return Clock.init(self, FixedClock.nanoTimestamp)
    }
};

var my_fixed_clock = FixedClock{ .fixed_time = 1234567890_000_000_000 };

var clock_seq = LocalClockSequence(Uuid.V7.Timestamp){
    .clock = my_fixed_clock.toClock(),
};

const uuid: Uuid = .{ .v7 = .init(clock_seq.next()) };
```

## Examples

There is example code in `example.zig`. You can run them:

```bash
zig build example
```

## Benchmarking

In case you care about generating UUIDs faster than you can put them anywhere, there's a benchmark:

```bash
zig build bench
```

## License

MIT
