# uuidz

RFC 9562 compliant UUID implementation for Zig.

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

// Random UUID (v4)
const uuid = Uuid{ .v4 = .init() };

// Time-based UUID (v7)
const time_uuid = Uuid{ .v7 = .now() };

// Name-based UUID (v5)
const name_uuid = Uuid{ .v5 = .init(Uuid.namespace.dns, "example.com") };

// Convert formats
const bytes = uuid.toBytes();
const int = uuid.toNative();
const from_bytes = Uuid.fromBytes(bytes);
```

## UUID Versions

```zig
// v1: MAC + timestamp
Uuid{ .v1 = .now(0x001122334455) }

// v3: MD5 hash
Uuid{ .v3 = .init(namespace, "name") }

// v4: Random
Uuid{ .v4 = .init() }

// v5: SHA-1 hash
Uuid{ .v5 = .init(namespace, "name") }

// v6: Reordered time
Uuid{ .v6 = .now(0x001122334455) }

// v7: Unix timestamp
Uuid{ .v7 = .now() }

// v8: Custom
Uuid{ .v8 = .init(0x123456789abcdef) }
```

## API

### Core Methods

- `fromBytes([16]u8) Uuid`
- `toBytes() [16]u8`
- `eql(Uuid) bool`
- `getVersion() ?Version`

### Constants

- `Uuid.Nil` - nil UUID
- `Uuid.Max` - max UUID
- `Uuid.namespace.{dns,url,oid,x500}` - standard namespaces

### Type-Safe Versions

For when you need to ensure a specific version:

```zig
const v7_uuid: Uuid.V7 = .now();
const generic_uuid = v7_uuid.toUuid();
```

### Clock Sequences & Entropy

For time-based UUIDs (v1, v6, v7), clock sequences ensure uniqueness when generating multiple UUIDs at the same timestamp:

```zig
const uuidz = @import("uuidz");

var clock_seq = uuidz.ClockSequence(uuidz.Uuid.V7.Timestamp){
    .clock = uuidz.Clock.System,
    .rand = std.crypto.random,
};

const ts = clock_seq.next();
const uuid = uuidz.Uuid{ .v7 = .init(ts) };
```

You'll notice you can also provide your own random number generator. Built-in sequences:

- `ClockSequence(...).System` - uses system clock
- `ClockSequence(...).Zero` - uses zero clock (for testing)

### Custom Clocks

You can create and use your own clocks if you need custom timestamp behavior:

```zig
const FixedClock = struct {
    fixed_time: i128,

    fn nanoTimestamp(self: *FixedClock) i128 {
        return self.fixed_time;
    }

    fn toClock(self: *FixedClock) Clock {
        return uuidz.Clock.init(self, FixedClock.nanoTimestamp)
    }
};

var my_fixed_clock = FixedClock{ .fixed_time = 1234567890_000_000_000 };

var clock_seq = uuidz.ClockSequence(uuidz.Uuid.V7.Timestamp){
    .clock = my_fixed_clock.toClock(),
};

const ts = clock_seq.next();
const uuid = Uuid { .v7 = .init(ts) };
```

## Testing

```bash
zig build test
```

## License

MIT
