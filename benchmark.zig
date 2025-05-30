const std = @import("std");
const Uuid = @import("src/root.zig").Uuid;

const ITERATIONS = 1_000_000;
const WARMUP_ITERATIONS = 10_000;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var warmup_seq = Uuid.AtomicClockSequence(Uuid.V7.Timestamp){
        .clock = .system,
        .rand = std.crypto.random,
    };
    for (0..WARMUP_ITERATIONS) |_| {
        _ = warmup_seq.next();
    }

    std.debug.print("Single-threaded comparison:\n", .{});
    const atomic_ns_per_op = try benchmarkSingleThreaded();

    std.debug.print("\nMulti-threaded performance:\n", .{});
    for ([_]u32{ 2, 4, 8 }) |threads| {
        try benchmarkMultiThreaded(threads, allocator, atomic_ns_per_op);
    }

    std.debug.print("\nStress test:\n", .{});
    try benchmarkStressTest(allocator);

    std.debug.print("\nParsing benchmark:\n", .{});
    try benchmarkParsing(allocator);
}

fn benchmarkSingleThreaded() !u64 {
    var local_seq = Uuid.LocalClockSequence(Uuid.V7.Timestamp){
        .clock = .system,
        .rand = std.crypto.random,
    };
    var timer = try std.time.Timer.start();
    for (0..ITERATIONS) |_| {
        _ = local_seq.next();
    }
    const local_ns = timer.read();
    const local_ns_per_op = local_ns / ITERATIONS;
    const local_ops_per_sec = @as(f64, std.time.ns_per_s) / @as(f64, @floatFromInt(local_ns_per_op));

    var atomic_seq = Uuid.AtomicClockSequence(Uuid.V7.Timestamp){
        .clock = .system,
        .rand = std.crypto.random,
    };
    timer.reset();
    for (0..ITERATIONS) |_| {
        _ = atomic_seq.next();
    }
    const atomic_ns = timer.read();
    const atomic_ns_per_op = atomic_ns / ITERATIONS;
    const atomic_ops_per_sec = @as(f64, std.time.ns_per_s) / @as(f64, @floatFromInt(atomic_ns_per_op));

    const overhead = (@as(f64, @floatFromInt(atomic_ns_per_op)) / @as(f64, @floatFromInt(local_ns_per_op)) - 1.0) * 100.0;

    std.debug.print("  Local:  {d:.0} ops/sec ({} ns/op)\n", .{ local_ops_per_sec, local_ns_per_op });
    std.debug.print("  Atomic: {d:.0} ops/sec ({} ns/op)\n", .{ atomic_ops_per_sec, atomic_ns_per_op });
    std.debug.print("  Overhead: {d:.1}%\n", .{overhead});

    return atomic_ns_per_op;
}

fn benchmarkMultiThreaded(thread_count: u32, allocator: std.mem.Allocator, baseline_ns_per_op: u64) !void {
    const iterations_per_thread = ITERATIONS / thread_count;
    const total_operations = thread_count * iterations_per_thread;

    var shared_seq = Uuid.AtomicClockSequence(Uuid.V7.Timestamp){
        .clock = .system,
        .rand = std.crypto.random,
    };

    const WorkerContext = struct {
        seq: *Uuid.AtomicClockSequence(Uuid.V7.Timestamp),
        iterations: u32,

        fn run(self: @This()) void {
            for (0..self.iterations) |_| {
                _ = self.seq.next();
            }
        }
    };

    const threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var timer = try std.time.Timer.start();

    for (threads) |*thread| {
        const context = WorkerContext{ .seq = &shared_seq, .iterations = iterations_per_thread };
        thread.* = try std.Thread.spawn(.{}, WorkerContext.run, .{context});
    }

    for (threads) |thread| {
        thread.join();
    }

    const elapsed_ns = timer.read();
    const ns_per_op = elapsed_ns / total_operations;
    const ops_per_sec = @as(f64, std.time.ns_per_s) / @as(f64, @floatFromInt(ns_per_op));
    const slowdown = @as(f64, @floatFromInt(ns_per_op)) / @as(f64, @floatFromInt(baseline_ns_per_op));

    std.debug.print("  {} threads: {d:.0} ops/sec ({} ns/op) - {d:.1}x slower\n", .{ thread_count, ops_per_sec, ns_per_op, slowdown });
}

fn benchmarkStressTest(allocator: std.mem.Allocator) !void {
    const thread_count = 32;
    const iterations_per_thread = 10_000;
    const total_operations = thread_count * iterations_per_thread;

    var shared_seq = Uuid.AtomicClockSequence(Uuid.V7.Timestamp){
        .clock = .system,
        .rand = std.crypto.random,
    };

    const StressWorkerContext = struct {
        seq: *Uuid.AtomicClockSequence(Uuid.V7.Timestamp),
        iterations: u32,

        fn run(self: @This()) void {
            for (0..self.iterations) |_| {
                _ = self.seq.next();
                for (0..10) |_| {
                    std.atomic.spinLoopHint();
                }
            }
        }
    };

    const threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var timer = try std.time.Timer.start();

    for (threads) |*thread| {
        const context = StressWorkerContext{ .seq = &shared_seq, .iterations = iterations_per_thread };
        thread.* = try std.Thread.spawn(.{}, StressWorkerContext.run, .{context});
    }

    for (threads) |thread| {
        thread.join();
    }

    const elapsed_ns = timer.read();
    const ns_per_op = elapsed_ns / total_operations;
    const ops_per_sec = @as(f64, std.time.ns_per_s) / @as(f64, @floatFromInt(ns_per_op));

    std.debug.print("  {} threads with contention: {d:.0} ops/sec ({} ns/op)\n", .{ thread_count, ops_per_sec, ns_per_op });
}

fn benchmarkParsing(allocator: std.mem.Allocator) !void {
    var seq = Uuid.LocalClockSequence(Uuid.V7.Timestamp){
        .clock = .system,
        .rand = std.crypto.random,
    };

    const uuid_strings = try allocator.alloc([36]u8, ITERATIONS);
    defer allocator.free(uuid_strings);

    for (0..ITERATIONS) |i| {
        const uuid = Uuid.V7.init(seq.next());
        uuid_strings[i] = uuid.toString();
    }

    var timer = try std.time.Timer.start();

    for (uuid_strings) |uuid_str| {
        _ = Uuid.parse(&uuid_str) catch unreachable;
    }

    const elapsed_ns = timer.read();
    const ns_per_op = elapsed_ns / ITERATIONS;
    const ops_per_sec = @as(f64, std.time.ns_per_s) / @as(f64, @floatFromInt(ns_per_op));

    std.debug.print("  Parse: {d:.0} ops/sec ({} ns/op)\n", .{ ops_per_sec, ns_per_op });
}
