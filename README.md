# uuidz

An [RFC 9562](https://datatracker.ietf.org/doc/html/rfc9562) compliant UUID implementation for Zig.

## About

- **Version support**: Implements all UUID versions including the latest v6, v7, and v8
- **Type safety**: Use the `Uuid` union to accept any version, or `Uuid.V7` to only accept V7 UUIDs
- **Thread safety**: Generate time-based UUIDs from multiple threads without coordination or duplicate values
- **Packed structs**: All UUID types can cast directly to integers and work with raw bytes without overhead
- **Compliant**: Generates UUIDs with correct bit layouts, version/variant fields, and timestamp formats
- **Non-compliant**: Represent UUIDs that don't follow RFC 9562 for interoperability
- **Flexible clocks**: Configurable clock sources for time-based UUIDs with multi and single-threaded implementations
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
const t4: Uuid.V4 = .init(std.crypto.random);
const t5: Uuid.V5 = .init(.dns, "tristanpemble.com");
const t6: Uuid.V6 = .now(0x001122334455);
const t7: Uuid.V7 = .now();
const t8: Uuid.V8 = .init(0x123456789abcdef);

// Union type to accept any version
const u1: Uuid = .{ .v1 = .now(0x001122334455) };
const u3: Uuid = .{ .v3 = .init(.dns, "tristanpemble.com") };
const u4: Uuid = .{ .v4 = .init(std.crypto.random) };
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

- `SafeClockSequence`: The default, slower, thread-safe, unpredictable sequence for maximum safety.
- `FastClockSequence`: Faster, single-threaded, predictable sequence for maximum throughput.

They both ensure monotonicity. The trade-off is between speed and security. Both implementations accept a `Clock`,
so that you can customize their behavior. We provide two clocks:

- `Clock.system`: Uses the system clock to generate timestamps.
- `Clock.zero`: Always returns zero.

The `SafeClockSequence` also accept a `std.Random`, allowing you to use a custom random number generator, or reduce its
entropy for increased performance. It defaults to `std.crypto.random`.

For example, to use a `SafeClockSequence`, that only outputs a zero timestamp:

```zig
var clock_seq = Uuid.SafeClockSequence(Uuid.V7.Timestamp){
    .clock = .zero,
};

const uuid: Uuid.V7 = .init(clock_seq.next());
```

### SafeClockSequence

The current implementation of `SafeClockSequence` was coded for correctness (as far as I can verify it), and not
performance. I am not an expert in lockless concurrent algorithms. My hope is that someone more capable may provide
a faster implementation in the future. In the end, it is more than sufficiently performant for the most typical usecases.

The algorithm works like this:

- Get the current timestamp.
- If the timestamp increased monotonically:
  - Generate a new cryptographically secure random sequence value.
  - If the sequence increment overflowed, wait for the next tick.
- If the timestamp did not increase monotonically, replace the sequence with a new cryptographically secure random value.

This all occurs in an atomic compare-and-swap loop until the we obtain a unique timestamp and sequence counter.

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
benchmark        n  runs        total     avg ±     σ   min ...   max     p75    p99   p995
-------------------------------------------------------------------------------------------
Uuid.parse       1  100000      2.0us    20ns ±   6ns  18ns ...  81ns    19ns   81ns   81ns
Uuid.toString    1  100000    434.0ns     4ns ±   0ns   4ns ...   6ns     5ns    6ns    6ns
Uuid.V1 fast     1  100000      2.5us    24ns ±   1ns  24ns ...  32ns    25ns   32ns   32ns
Uuid.V1 safe     1  100000     24.5us   244ns ±   6ns 232ns ... 260ns   250ns  260ns  260ns
Uuid.V1 safe     2  200000     40.9us   408ns ±  12ns 379ns ... 441ns   417ns  441ns  441ns
Uuid.V1 safe     4  400000     39.0us   390ns ±  20ns 368ns ... 499ns   393ns  499ns  499ns
Uuid.V1 safe     8  800000     47.0us   469ns ±  21ns 424ns ... 523ns   488ns  523ns  523ns
Uuid.V3          1  100000    636.0ns     6ns ±   0ns   6ns ...   7ns     7ns    7ns    7ns
Uuid.V4          1  100000      8.0us    80ns ±   1ns  78ns ...  95ns    80ns   95ns   95ns
Uuid.V5          1  100000    621.0ns     6ns ±   0ns   6ns ...   8ns     6ns    8ns    8ns
Uuid.V6 fast     1  100000      2.5us    25ns ±   1ns  25ns ...  31ns    25ns   31ns   31ns
Uuid.V6 safe     1  100000     24.7us   246ns ±   6ns 235ns ... 270ns   250ns  270ns  270ns
Uuid.V6 safe     2  200000     40.5us   404ns ±  11ns 377ns ... 438ns   413ns  438ns  438ns
Uuid.V6 safe     4  400000     38.7us   387ns ±  16ns 368ns ... 501ns   390ns  501ns  501ns
Uuid.V6 safe     8  800000     46.7us   467ns ±  23ns 427ns ... 517ns   484ns  517ns  517ns
Uuid.V7 fast     1  100000      2.4us    24ns ±   1ns  23ns ...  30ns    24ns   30ns   30ns
Uuid.V7 safe     1  100000      5.8us    57ns ±   2ns  57ns ...  83ns    57ns   83ns   83ns
Uuid.V7 safe     2  200000     14.4us   144ns ±   8ns  96ns ... 166ns   149ns  166ns  166ns
Uuid.V7 safe     4  400000     19.0us   190ns ±   9ns 176ns ... 231ns   192ns  231ns  231ns
Uuid.V7 safe     8  800000     20.0us   199ns ±   8ns 178ns ... 221ns   207ns  221ns  221ns
```

## License

MIT
