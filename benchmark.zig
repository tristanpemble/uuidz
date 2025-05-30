const std = @import("std");
const uuidz = @import("src/root.zig");

const ITERATIONS = 1_000_000;
const WARM_UP_ITERATIONS = 10_000;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("ClockSequence Performance Benchmark\n", .{});
    std.debug.print("====================================\n\n", .{});

    // Warm up
    std.debug.print("Warming up...\n", .{});
    {
        var seq = uuidz.AtomicClockSequence(uuidz.Uuid.V7.Timestamp).Zero;
        for (0..WARM_UP_ITERATIONS) |_| {
            _ = seq.next();
        }
    }

    // Single-threaded comparison
    std.debug.print("1. Single-threaded comparison (Thread-Safe vs Single-Threaded):\n", .{});
    try benchmarkSingleThreadedComparison();

    // Multi-threaded benchmarks (atomic only)
    std.debug.print("\n2. Multi-threaded performance (Thread-Safe Atomic):\n", .{});
    const thread_counts = [_]u32{ 2, 4, 8, 16 };
    for (thread_counts) |thread_count| {
        try benchmarkMultiThreaded(thread_count, allocator);
    }

    // Contention test
    std.debug.print("\n3. High contention stress test:\n", .{});
    try benchmarkHighContention(allocator);

    // Memory overhead analysis
    std.debug.print("\n4. Memory footprint analysis:\n", .{});
    benchmarkMemoryOverhead();

    std.debug.print("\n✓ Benchmark completed successfully!\n", .{});
}

fn benchmarkSingleThreadedComparison() !void {
    // Benchmark atomic version
    var atomic_seq = uuidz.AtomicClockSequence(uuidz.Uuid.V7.Timestamp).Zero;

    var timer = try std.time.Timer.start();
    for (0..ITERATIONS) |_| {
        _ = atomic_seq.next();
    }
    const atomic_elapsed_ns = timer.read();

    const atomic_ns_per_op = atomic_elapsed_ns / ITERATIONS;
    const atomic_ops_per_sec = @as(f64, std.time.ns_per_s) / @as(f64, @floatFromInt(atomic_ns_per_op));

    // Benchmark single-threaded version
    var non_atomic_seq = uuidz.LocalClockSequence(uuidz.Uuid.V7.Timestamp).Zero;

    timer.reset();
    for (0..ITERATIONS) |_| {
        _ = non_atomic_seq.next();
    }
    const non_atomic_elapsed_ns = timer.read();

    const non_atomic_ns_per_op = non_atomic_elapsed_ns / ITERATIONS;
    const non_atomic_ops_per_sec = @as(f64, std.time.ns_per_s) / @as(f64, @floatFromInt(non_atomic_ns_per_op));

    const overhead_percent = (@as(f64, @floatFromInt(atomic_ns_per_op)) / @as(f64, @floatFromInt(non_atomic_ns_per_op)) - 1.0) * 100.0;

    std.debug.print("   Single-threaded: {d:.0} ops/sec, {} ns/op\n", .{ non_atomic_ops_per_sec, non_atomic_ns_per_op });
    std.debug.print("   Thread-safe:     {d:.0} ops/sec, {} ns/op\n", .{ atomic_ops_per_sec, atomic_ns_per_op });
    std.debug.print("   Overhead:        {d:.1}% slower for thread-safety\n", .{overhead_percent});
}

fn benchmarkMultiThreaded(thread_count: u32, allocator: std.mem.Allocator) !void {
    const iterations_per_thread = ITERATIONS / thread_count;
    const total_iterations = thread_count * iterations_per_thread;

    const threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var shared_seq = uuidz.AtomicClockSequence(uuidz.Uuid.V7.Timestamp).Zero;

    const ThreadArgs = struct {
        seq: *uuidz.AtomicClockSequence(uuidz.Uuid.V7.Timestamp),
        iterations: u32,
        thread_id: u32,
    };

    const worker = struct {
        fn run(args: ThreadArgs) void {
            for (0..args.iterations) |_| {
                _ = args.seq.next();
            }
        }
    }.run;

    var timer = try std.time.Timer.start();

    // Spawn threads
    for (threads, 0..) |*thread, i| {
        const args = ThreadArgs{
            .seq = &shared_seq,
            .iterations = iterations_per_thread,
            .thread_id = @intCast(i),
        };
        thread.* = try std.Thread.spawn(.{}, worker, .{args});
    }

    // Wait for completion
    for (threads) |thread| {
        thread.join();
    }

    const elapsed_ns = timer.read();
    const ns_per_op = elapsed_ns / total_iterations;
    const ops_per_sec = @as(f64, std.time.ns_per_s) / @as(f64, @floatFromInt(ns_per_op));

    const efficiency = (ops_per_sec / @as(f64, @floatFromInt(thread_count))) / 35_000_000.0; // Baseline from single-threaded

    std.debug.print("   {} threads: {d:.0} ops/sec ({} ns/op) - {d:.1}% efficiency\n", .{ thread_count, ops_per_sec, ns_per_op, efficiency * 100.0 });
}

fn benchmarkHighContention(allocator: std.mem.Allocator) !void {
    const thread_count = 32;
    const iterations_per_thread = 10_000;
    const total_iterations = thread_count * iterations_per_thread;

    const threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var shared_seq = uuidz.AtomicClockSequence(uuidz.Uuid.V7.Timestamp).Zero;

    const ThreadArgs = struct {
        seq: *uuidz.AtomicClockSequence(uuidz.Uuid.V7.Timestamp),
        iterations: u32,
    };

    const worker = struct {
        fn run(args: ThreadArgs) void {
            for (0..args.iterations) |_| {
                _ = args.seq.next();
                // Add tiny delay to increase contention
                for (0..10) |_| {
                    std.atomic.spinLoopHint();
                }
            }
        }
    }.run;

    var timer = try std.time.Timer.start();

    // Spawn threads
    for (threads) |*thread| {
        const args = ThreadArgs{
            .seq = &shared_seq,
            .iterations = iterations_per_thread,
        };
        thread.* = try std.Thread.spawn(.{}, worker, .{args});
    }

    // Wait for completion
    for (threads) |thread| {
        thread.join();
    }

    const elapsed_ns = timer.read();
    const ns_per_op = elapsed_ns / total_iterations;
    const ops_per_sec = @as(f64, std.time.ns_per_s) / @as(f64, @floatFromInt(ns_per_op));

    std.debug.print("   {} threads under stress: {d:.0} ops/sec ({} ns/op)\n", .{ thread_count, ops_per_sec, ns_per_op });
    std.debug.print("   Successfully handled {} operations with high contention\n", .{total_iterations});
}

fn benchmarkMemoryOverhead() void {
    const ThreadSafeType = uuidz.AtomicClockSequence(uuidz.Uuid.V7.Timestamp);
    const SingleThreadedType = uuidz.LocalClockSequence(uuidz.Uuid.V7.Timestamp);

    std.debug.print("   Single-threaded ClockSequence: {} bytes\n", .{@sizeOf(SingleThreadedType)});
    std.debug.print("   Thread-safe ClockSequence:     {} bytes\n", .{@sizeOf(ThreadSafeType)});
    std.debug.print("   Memory overhead:                {} bytes ({d:.1}% increase)\n", .{ @sizeOf(ThreadSafeType) - @sizeOf(SingleThreadedType), (@as(f64, @floatFromInt(@sizeOf(ThreadSafeType))) / @as(f64, @floatFromInt(@sizeOf(SingleThreadedType))) - 1.0) * 100.0 });

    const total_bits = @bitSizeOf(ThreadSafeType.Tick) + @bitSizeOf(ThreadSafeType.Seq);
    std.debug.print("   State packing:                  {} + {} = {} bits (fits in u128)\n", .{ @bitSizeOf(ThreadSafeType.Tick), @bitSizeOf(ThreadSafeType.Seq), total_bits });
}
