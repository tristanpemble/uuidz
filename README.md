# uuidz

An [RFC 9562](https://datatracker.ietf.org/doc/html/rfc9562) compliant UUID implementation for Zig.

## About

- **Version support**: Implements all UUID versions including the latest v6, v7, and v8
- **Type safety**: Use the `Uuid` union to accept any version, or `Uuid.V7` to only accept V7 UUIDs
- **Thread safety**: Generate time-based UUIDs from multiple threads without coordination or duplicate values
- **Packed structs**: All UUID types can cast directly to integers and work with raw bytes without overhead
- **Compliant**: Generates UUIDs with correct bit layouts, version/variant fields, and timestamp formats
- **Non-compliant**: Represent UUIDs that don't follow RFC 9562 for interoperability
- **Flexible clocks**: Configurable clock sources for time-based UUIDs with atomic and local implementations
- **Zero dependencies**: Uses only Zig's standard library

The design is heavily influenced by the Rust [uuid](https://github.com/uuid-rs/uuid) crate, with some Zig specific flavoring.

## Documentation

See the [API reference documentation](https://tristanpemble.github.io/uuidz/) on the GitHub pages.

## Installation

```bash
zig fetch --save git+https://github.com/tristanpemble/uuidz.git
```

Then add to your `build.zig`:

```zig
const uuidz = b.dependency("uuidz", .{});
exe.root_module.addImport("uuidz", uuidz.module("uuidz"));
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
const uuid = try Uuid.parse("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
const uuid_ne: Uuid = .fromNative(0x6ba7b810_9dad_11d1_80b4_00c04fd430c8);
const uuid_be: Uuid = .fromBig(0x6ba7b810_9dad_11d1_80b4_00c04fd430c8);
const uuid_le: Uuid = .fromLittle(0x6ba7b810_9dad_11d1_80b4_00c04fd430c8);
const uuid_by: Uuid = .fromBytes(.{0x6b,0xa7,0xb8,0x10,0x9d,0xad,0x11,0xd1,0x80,0xb4,0x00,0xc0,0x4f,0xd4,0x30,0xc8});
const int_ne: u128 = uuid.toNative();
const int_be: u128 = uuid.toBig();
const int_le: u128 = uuid.toLittle();
const bytes: [16]u8 = uuid.toBytes();
const string: [36]u8 = uuid.toString();

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

For time-based UUIDs (v1, v6, v7), clock sequences ensure uniqueness when multiple UUIDs are generated at the same
timestamp. It does this by using a random initial sequence value that increments for each UUID within the same tick,
as per RFC9562.

We provide two ClockSequence implementations, but you are free to write your own:

- `AtomicClockSequence`: The default, a lock-free, thread-safe implementation.
- `LocalClockSequence`: A single-threaded implementation for maximum throughput.

Both implementations accept a `Clock`, so that you can customize their behavior. We provide two clocks:

- `Clock.system`: Uses the system clock to generate timestamps.
- `Clock.zero`: Always returns zero.

They also accept a `std.Random`, allowing you to use a custom random number generator.

For example, to use a single-threaded `LocalClockSequence`, that only outputs zero, with a PRNG, to generate a v7 UUID:

```zig
var rng = std.Random.DefaultPrng.init(0);
var clock_seq = Uuid.LocalClockSequence(Uuid.V7.Timestamp){
    .clock = .zero,
    .rand = rng.random(),
};

const uuid: Uuid.V7 = .init(clock_seq.next());
```

### Custom Clocks

You can create and use your own clocks if you need custom behavior for your usecase.

```zig
const FixedClock = struct {
    fixed_ns: i128,

    fn nanoTimestamp(self: *FixedClock) i128 {
        return self.fixed_ns;
    }

    fn toClock(self: *FixedClock) Clock {
        return Uuid.Clock.init(self, FixedClock.nanoTimestamp)
    }
};
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

On my MacBook Pro M4 Max, the results are:

```
Single-threaded comparison:
  Local:  47619048 ops/sec (21 ns/op)
  Atomic: 43478261 ops/sec (23 ns/op)
  Overhead: 9.5%

Multi-threaded performance:
  2 threads: 21739130 ops/sec (46 ns/op) - 2.0x slower
  4 threads: 9900990 ops/sec (101 ns/op) - 4.4x slower
  8 threads: 5681818 ops/sec (176 ns/op) - 7.7x slower

Stress test:
  32 threads with contention: 2024291 ops/sec (494 ns/op)

Parsing benchmark:
  Parse: 76923077 ops/sec (13 ns/op)
```

## License

MIT
