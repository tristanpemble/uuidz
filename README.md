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
- If the timestamp did not increase monotonically:
  - Increment the sequence value with a new cryptographically secure random value.
  - If this would cause an overflow, try again.

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

On my AMD Ryzen 9 5950X, the results are:

```
benchmark        n  runs        total     avg ±     σ   min ...   max     p75    p99   p995
-------------------------------------------------------------------------------------------
uuidz.parse      1  1000000   174.8ms     2ms ±  99us   2ms ...   2ms     2ms    2ms    2ms
uuidz.toString   1  1000000     7.2ms    72us ±   8us  66us ... 116us    70us  116us  116us
uuidz.V1 fast    1  1000000    28.6ms   286us ±   5us 279us ... 301us   288us  301us  301us
uuidz.V1 safe    1  1000000    64.1ms   641us ±  27us 619us ... 766us   646us  766us  766us
uuidz.V1 safe    2  1000000    99.4ms   994us ± 213us 803us ...   2ms     1ms    2ms    2ms
uuidz.V1 safe    4  1000000   143.7ms     1ms ± 165us 989us ...   2ms     2ms    2ms    2ms
uuidz.V1 safe    8  1000000   197.8ms     2ms ± 192us   1ms ...   2ms     2ms    2ms    2ms
uuidz.V3         1  1000000    86.9ms   869us ±  63us 824us ...   1ms   864us    1ms    1ms
uuidz.V4         1  1000000    10.0ms   100us ±  15us  91us ... 151us   100us  151us  151us
uuidz.V5         1  1000000    75.3ms   753us ±   6us 737us ... 772us   756us  772us  772us
uuidz.V6 fast    1  1000000    28.8ms   288us ±   3us 283us ... 299us   290us  299us  299us
uuidz.V6 safe    1  1000000    63.2ms   632us ±   4us 623us ... 657us   634us  657us  657us
uuidz.V6 safe    2  1000000   103.8ms     1ms ± 198us 855us ...   2ms     1ms    2ms    2ms
uuidz.V6 safe    4  1000000   145.1ms     1ms ± 155us 954us ...   2ms     2ms    2ms    2ms
uuidz.V6 safe    8  1000000   207.2ms     2ms ± 122us   2ms ...   2ms     2ms    2ms    2ms
uuidz.V7 fast    1  1000000    39.5ms   395us ±  35us 366us ... 500us   408us  500us  500us
uuidz.V7 safe    1  1000000    51.1ms   511us ±   4us 503us ... 525us   514us  525us  525us
uuidz.V7 safe    2  1000000    85.0ms   850us ± 136us 699us ...   1ms   889us    1ms    1ms
uuidz.V7 safe    4  1000000   143.7ms     1ms ± 190us 995us ...   2ms     2ms    2ms    2ms
uuidz.V7 safe    8  1000000   179.1ms     2ms ± 119us   1ms ...   2ms     2ms    2ms    2ms
uuid_zig.V4      1  1000000     9.2ms    92us ±  13us  84us ... 181us    93us  181us  181us
uuid_zig.V7      1  1000000    36.6ms   366us ±  31us 346us ... 478us   369us  478us  478us
```

## License

MIT
