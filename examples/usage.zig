const std = @import("std");
const Uuid = @import("uuidz").Uuid;

pub fn main() !void {
    // Random UUID
    const v4 = Uuid{ .v4 = .init() };
    std.debug.print("v4: {}\n", .{v4});

    // Time-based UUID
    const v7 = Uuid{ .v7 = .now() };
    std.debug.print("v7: {}\n", .{v7});

    // Name-based UUID
    const v5 = Uuid{ .v5 = .init(Uuid.namespace.dns, "example.com") };
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
    std.debug.print("nil: {}\n", .{Uuid.Nil});
    std.debug.print("max: {}\n", .{Uuid.Max});
}
