const std = @import("std");
const Uuid = @import("src/uuidz.zig").Uuid;
const uuid_zig = @import("uuid_zig");

const RUNS = 1_000_000;
const SAMPLES = 100;
const WARMUP_RUNS = 1000;

const BenchmarkResult = struct {
    name: []const u8,
    threads: u32,
    total_ops: u32,
    samples: [SAMPLES]u64,

    fn calculate(self: *const BenchmarkResult) Stats {
        var sorted: [SAMPLES]u64 = self.samples;
        std.sort.heap(u64, &sorted, {}, std.sort.asc(u64));

        var total: u64 = 0;
        for (self.samples) |sample| {
            total += sample;
        }
        const avg = total / SAMPLES;

        var variance: f64 = 0;
        for (self.samples) |sample| {
            const diff = @as(f64, @floatFromInt(sample)) - @as(f64, @floatFromInt(avg));
            variance += diff * diff;
        }
        variance /= @as(f64, @floatFromInt(SAMPLES));
        const std_dev = @sqrt(variance);

        const p75_idx = @min((SAMPLES * 75) / 100, SAMPLES - 1);
        const p99_idx = @min((SAMPLES * 99) / 100, SAMPLES - 1);
        const p995_idx = @min((SAMPLES * 995) / 1000, SAMPLES - 1);

        return Stats{
            .name = self.name,
            .threads = self.threads,
            .runs = self.total_ops,
            .total_time_ns = total,
            .avg_ns = avg,
            .std_dev_ns = @as(u64, @intFromFloat(@max(0, std_dev))),
            .min_ns = sorted[0],
            .max_ns = sorted[SAMPLES - 1],
            .p75_ns = sorted[p75_idx],
            .p99_ns = sorted[p99_idx],
            .p995_ns = sorted[p995_idx],
        };
    }
};

const Stats = struct {
    name: []const u8,
    threads: u32,
    runs: u32,
    total_time_ns: u64,
    avg_ns: u64,
    std_dev_ns: u64,
    min_ns: u64,
    max_ns: u64,
    p75_ns: u64,
    p99_ns: u64,
    p995_ns: u64,

    fn formatTime(ns: u64) struct { value: f64, unit: []const u8 } {
        if (ns >= 1_000_000_000) {
            return .{ .value = @as(f64, @floatFromInt(ns)) / std.time.ns_per_s, .unit = "s" };
        } else if (ns >= 1_000_000) {
            return .{ .value = @as(f64, @floatFromInt(ns)) / std.time.ns_per_ms, .unit = "ms" };
        } else if (ns >= 1_000) {
            return .{ .value = @as(f64, @floatFromInt(ns)) / std.time.ns_per_us, .unit = "us" };
        } else {
            return .{ .value = @as(f64, @floatFromInt(ns)), .unit = "ns" };
        }
    }

    fn print(self: Stats) void {
        const total = formatTime(self.total_time_ns);
        const avg = formatTime(self.avg_ns);
        const std_dev = formatTime(self.std_dev_ns);
        const min_time = formatTime(self.min_ns);
        const max_time = formatTime(self.max_ns);
        const p75 = formatTime(self.p75_ns);
        const p99 = formatTime(self.p99_ns);
        const p995 = formatTime(self.p995_ns);

        std.debug.print("{s:<16} {d:<2} {d:<8} {d:>6.1}{s:<3} {d:>4.0}{s:<2} ± {d:>3.0}{s:<2} {d:>3.0}{s:<2} ... {d:>3.0}{s:<3} {d:>4.0}{s:<2} {d:>4.0}{s:<2} {d:>4.0}{s}\n", .{
            self.name,
            self.threads,
            self.runs,
            total.value,
            total.unit,
            avg.value,
            avg.unit,
            std_dev.value,
            std_dev.unit,
            min_time.value,
            min_time.unit,
            max_time.value,
            max_time.unit,
            p75.value,
            p75.unit,
            p99.value,
            p99.unit,
            p995.value,
            p995.unit,
        });
    }
};

fn benchmarkFunction(comptime name: []const u8, comptime thread_count: u32, work_fn: *const fn (u32) void) void {
    var samples: [SAMPLES]u64 = undefined;
    const total_ops = RUNS * thread_count;
    const ops_per_sample = total_ops / SAMPLES;

    // Warmup phase to avoid cold-start effects
    if (thread_count == 1) {
        // Single-threaded warmup
        for (0..WARMUP_RUNS) |j| {
            work_fn(@as(u32, @intCast(j)));
        }
    } else {
        // Multi-threaded warmup
        const warmup_per_thread = WARMUP_RUNS / thread_count;
        var warmup_threads: [thread_count]std.Thread = undefined;

        const WarmupContext = struct {
            work_fn: *const fn (u32) void,
            ops_count: u32,

            fn run(self: @This()) void {
                for (0..self.ops_count) |j| {
                    self.work_fn(@as(u32, @intCast(j)));
                }
            }
        };

        for (0..thread_count) |t| {
            const context = WarmupContext{
                .work_fn = work_fn,
                .ops_count = warmup_per_thread,
            };
            warmup_threads[t] = std.Thread.spawn(.{}, WarmupContext.run, .{context}) catch unreachable;
        }

        for (0..thread_count) |t| {
            warmup_threads[t].join();
        }
    }

    if (thread_count == 1) {
        for (0..SAMPLES) |i| {
            var timer = std.time.Timer.start() catch unreachable;
            for (0..ops_per_sample) |j| {
                work_fn(@as(u32, @intCast(j)));
            }
            samples[i] = timer.read();
        }
    } else {
        const ops_per_thread = ops_per_sample / thread_count;

        const WorkerContext = struct {
            work_fn: *const fn (u32) void,
            ops_count: u32,
            timer: *std.time.Timer,
            ready: *std.Thread.ResetEvent,
            done: *std.Thread.ResetEvent,

            fn run(self: @This()) void {
                // Wait for all threads to be created
                self.ready.wait();

                // Start timing only the actual work
                self.timer.reset();
                for (0..self.ops_count) |j| {
                    self.work_fn(@as(u32, @intCast(j)));
                }

                // Signal completion
                self.done.set();
            }
        };

        for (0..SAMPLES) |i| {
            var threads: [8]std.Thread = undefined;
            var timer = std.time.Timer.start() catch unreachable;
            var ready = std.Thread.ResetEvent{};
            var done_events: [8]std.Thread.ResetEvent = undefined;

            for (0..thread_count) |t| {
                done_events[t] = std.Thread.ResetEvent{};
            }

            // Create all threads first (not timed)
            for (0..thread_count) |t| {
                const context = WorkerContext{
                    .work_fn = work_fn,
                    .ops_count = ops_per_thread,
                    .timer = &timer,
                    .ready = &ready,
                    .done = &done_events[t],
                };
                threads[t] = std.Thread.spawn(.{}, WorkerContext.run, .{context}) catch unreachable;
            }

            // Signal all threads to start work simultaneously
            ready.set();

            // Wait for all threads to complete
            for (0..thread_count) |t| {
                done_events[t].wait();
            }

            // Read the timer after all work is done
            samples[i] = timer.read();

            // Clean up threads
            for (0..thread_count) |t| {
                threads[t].join();
            }
        }
    }

    const result = BenchmarkResult{
        .name = name,
        .threads = thread_count,
        .total_ops = total_ops,
        .samples = samples,
    };
    result.calculate().print();
}

fn v1Benchmark(_: u32) void {
    const id = Uuid.V1.now(0x001122334455);
    std.mem.doNotOptimizeAway(id);
}

fn v3Benchmark(idx: u32) void {
    const test_strings = [_][]const u8{ "example.com", "test.org", "benchmark.net", "uuid.dev", "random.io" };
    const str = test_strings[idx % test_strings.len];
    const id = Uuid.V3.init(.dns, str);
    std.mem.doNotOptimizeAway(id);
}

fn v4Benchmark(_: u32) void {
    const id = Uuid.V4.init(std.crypto.random);
    std.mem.doNotOptimizeAway(id);
}

fn v5Benchmark(idx: u32) void {
    const test_strings = [_][]const u8{ "example.com", "test.org", "benchmark.net", "uuid.dev", "random.io" };
    const str = test_strings[idx % test_strings.len];
    const id = Uuid.V5.init(.dns, str);
    std.mem.doNotOptimizeAway(id);
}

fn v6Benchmark(_: u32) void {
    const id = Uuid.V6.now(0x001122334455);
    std.mem.doNotOptimizeAway(id);
}

fn v7Benchmark(_: u32) void {
    const id = Uuid.V7.now();
    std.mem.doNotOptimizeAway(id);
}

var v1_fast_seq = Uuid.FastClockSequence(Uuid.V1.Timestamp){ .clock = .system };
var v6_fast_seq = Uuid.FastClockSequence(Uuid.V6.Timestamp){ .clock = .system };
var v7_fast_seq = Uuid.FastClockSequence(Uuid.V7.Timestamp){ .clock = .system };

fn v1FastBenchmark(_: u32) void {
    const id = Uuid.V1.init(.fast(), 0x001122334455);
    std.mem.doNotOptimizeAway(id);
}

fn v6FastBenchmark(_: u32) void {
    const id = Uuid.V6.init(.fast(), 0x001122334455);
    std.mem.doNotOptimizeAway(id);
}

fn v7FastBenchmark(_: u32) void {
    const id = Uuid.V7.init(.fast());
    std.mem.doNotOptimizeAway(id);
}

var parse_strings: [1000][36]u8 = undefined;
var parse_initialized = false;

fn parseBenchmark(idx: u32) void {
    const id = Uuid.parse(&parse_strings[idx % parse_strings.len]) catch unreachable;
    std.mem.doNotOptimizeAway(id);
}

var toString_uuids: [1000]Uuid = undefined;
var toString_initialized = false;

fn toStringBenchmark(idx: u32) void {
    const str = toString_uuids[idx % toString_uuids.len].toString();
    std.mem.doNotOptimizeAway(&str);
}

fn uuidZigV4Benchmark(_: u32) void {
    const id = uuid_zig.v4.new();
    std.mem.doNotOptimizeAway(id);
}

fn uuidZigV7Benchmark(_: u32) void {
    const id = uuid_zig.v7.new();
    std.mem.doNotOptimizeAway(id);
}

pub fn main() !void {
    std.debug.print("benchmark        n  runs        total     avg ±     σ   min ...   max     p75    p99   p995\n", .{});
    std.debug.print("-------------------------------------------------------------------------------------------\n", .{});

    if (!parse_initialized) {
        for (0..parse_strings.len) |i| {
            const uuid = Uuid.V4.init(std.crypto.random);
            parse_strings[i] = uuid.toString();
        }
        parse_initialized = true;
    }
    benchmarkFunction("uuidz.parse", 1, parseBenchmark);

    if (!toString_initialized) {
        for (0..toString_uuids.len) |i| {
            toString_uuids[i] = Uuid{ .v4 = .init(std.crypto.random) };
        }
        toString_initialized = true;
    }
    benchmarkFunction("uuidz.toString", 1, toStringBenchmark);

    benchmarkFunction("uuidz.V1 fast", 1, v1FastBenchmark);
    inline for ([_]u32{ 1, 2, 4, 8 }) |thread_count| {
        benchmarkFunction("uuidz.V1 safe", thread_count, v1Benchmark);
    }

    benchmarkFunction("uuidz.V3", 1, v3Benchmark);
    benchmarkFunction("uuidz.V4", 1, v4Benchmark);
    benchmarkFunction("uuidz.V5", 1, v5Benchmark);

    benchmarkFunction("uuidz.V6 fast", 1, v6FastBenchmark);
    inline for ([_]u32{ 1, 2, 4, 8 }) |thread_count| {
        benchmarkFunction("uuidz.V6 safe", thread_count, v6Benchmark);
    }

    benchmarkFunction("uuidz.V7 fast", 1, v7FastBenchmark);
    inline for ([_]u32{ 1, 2, 4, 8 }) |thread_count| {
        benchmarkFunction("uuidz.V7 safe", thread_count, v7Benchmark);
    }

    benchmarkFunction("uuid_zig.V4", 1, uuidZigV4Benchmark);
    benchmarkFunction("uuid_zig.V7", 1, uuidZigV7Benchmark);
}
