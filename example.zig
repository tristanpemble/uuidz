const std = @import("std");
const Uuid = @import("uuidz").Uuid;

pub fn main() !void {
    // Parse UUID
    const uuid = try Uuid.parse("c232ab00-9414-11ec-b3c8-9f6bdeced846");
    std.debug.print("bytes: {any}\n", .{uuid.asSlice()});

    // Random UUID
    const v4 = Uuid{ .v4 = .init(std.crypto.random) };
    std.debug.print("v4: {}\n", .{v4});

    // Time-based UUID
    const v7 = Uuid{ .v7 = .now() };
    std.debug.print("v7: {}\n", .{v7});

    // Name-based UUID
    const v5 = Uuid{ .v5 = .init(.dns, "example.com") };
    std.debug.print("v5: {}\n", .{v5});

    // MAC + timestamp
    const v1 = Uuid{ .v1 = .now(0x001122334455) };
    std.debug.print("v1: {}\n", .{v1});

    // Format conversions
    const bytes = v4.toBytes();
    const from_bytes = Uuid.fromBytes(bytes);
    std.debug.print("round-trip: {}\n", .{v4.eql(from_bytes)});

    // Comparison
    std.debug.print("v7 > v4: {}\n", .{v7.order(v4) == .gt});

    // Type-safe versions (for when you need to ensure specific version)
    const v7_typed: Uuid.V7 = .now();
    const v7_generic = v7_typed.toUuid();
    std.debug.print("type-safe v7: {}\n", .{v7_generic});

    // Special UUIDs
    std.debug.print("nil: {}\n", .{Uuid.nil});
    std.debug.print("max: {}\n", .{Uuid.max});

    // Customize clock sequence
    var rng = std.Random.DefaultPrng.init(0);
    var clock_seq = Uuid.LocalClockSequence(Uuid.V7.Timestamp){
        .clock = .zero,
        .rand = rng.random(),
    };

    const v7_prng: Uuid.V7 = .init(clock_seq.next());
    std.debug.print("v7 Zero/PRNG: {}\n", .{v7_prng});
}
