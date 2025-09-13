const std = @import("std");
const builtin = @import("builtin");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
const count = 5;
const max_prime = 9999;
const sieve_size = 100_000_000;

pub fn main() !void {
    const allocator, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };

    defer if (is_debug) {
        switch (debug_allocator.deinit()) {
            .leak => std.debug.print("you leaked memory dum dum", .{}),
            .ok => {},
        }
    };

    var timer = try std.time.Timer.start();
    var prime_getter: PrimeGetter = undefined;
    try prime_getter.init(allocator, sieve_size);
    defer prime_getter.deinit(allocator);

    std.debug.print("prime count: {}\n", .{prime_getter.arr.bit_length});
    std.debug.print("prime init time {}ms\n", .{timer.lap() / std.time.ns_per_ms});

    const current_primes = try allocator.alloc(u32, count);
    defer allocator.free(current_primes);

    var last_prime: u32 = 1;
    for (current_primes) |*value| {
        last_prime = prime_getter.nextRestricted(last_prime, max_prime);
        value.* = last_prime;
    }

    var min_sum: u32 = std.math.maxInt(u32);

    main: while (true) {
        var k: u32 = prime_getter.checkIfFound(current_primes);
        if (k == 0) {
            var sum: u32 = 0;
            for (current_primes) |value| {
                sum += value;
            }
            if (sum < min_sum) {
                min_sum = sum;
            }
            k = @intCast(current_primes.len - 1);
            std.debug.print("found candidate: {}, primes: {any}\n", .{ sum, current_primes });
        }
        outer: while (k >= 0) : (k -= 1) {
            var o: u32 = k + 1;
            const next = prime_getter.nextRestricted(current_primes[k], max_prime);
            if (next != 0) {
                current_primes[k] = next;
                var last_set_prime = next;
                while (o < current_primes.len) : (o += 1) {
                    const next2 = prime_getter.nextRestricted(last_set_prime, max_prime);
                    if (next2 != 0) {
                        current_primes[o] = next2;
                        last_set_prime = next2;
                    } else {
                        if (k == 0) {
                            break :main;
                        }
                        continue :outer;
                    }
                }
                if (k == 0) {
                    var sum: u32 = 0;
                    for (current_primes) |value| {
                        sum += value;
                    }
                    if (min_sum < sum) {
                        std.debug.print("stopping early on: {}, {any}\n", .{ sum, current_primes });
                        break :main;
                    }
                }
                break :outer;
            }
        }
    }
    std.debug.print("answer: {}\n", .{min_sum});
}

const PrimeGetter = struct {
    arr: std.DynamicBitSetUnmanaged,
    const Self = @This();

    fn init(self: *Self, allocator: std.mem.Allocator, n: u32) !void {
        self.arr = try std.DynamicBitSetUnmanaged.initFull(allocator, n + 1);
        self.arr.unset(0);
        self.arr.unset(1);

        var i: u32 = 2;
        while (i < std.math.sqrt(n)) : (i += 1) {
            if (self.arr.isSet(i)) {
                var j: u32 = i * i;
                while (j <= n) : (j += i) {
                    self.arr.unset(j);
                }
            }
        }
    }

    fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.arr.deinit(allocator);
    }

    fn isPrime(self: Self, x: u32) bool {
        return self.arr.isSet(x);
    }

    fn nextRestricted(self: Self, x: u32, max: u32) u32 {
        var i: u32 = x + 1;
        while (i < max) : (i += 1) {
            if (self.arr.isSet(i)) {
                return i;
            }
        }
        return 0;
    }

    fn checkIfPairIsPrime(self: Self, a: u32, b: u32) bool {
        const a_len = std.math.log10(a) + 1;
        const b_len = std.math.log10(b) + 1;
        const new1 = a * std.math.pow(u32, 10, b_len) + b;
        const new2 = b * std.math.pow(u32, 10, a_len) + a;
        return self.isPrime(new1) and self.isPrime(new2);
    }

    fn checkIfFound(self: Self, arr: []u32) u32 {
        var i: u32 = 0;
        while (i < arr.len - 1) : (i += 1) {
            var j: u32 = i + 1;
            while (j < arr.len) : (j += 1) {
                if (!self.checkIfPairIsPrime(arr[i], arr[j])) {
                    return j;
                }
            }
        }
        return 0;
    }
};

test PrimeGetter {
    var prime_getter: PrimeGetter = undefined;
    try prime_getter.init(std.testing.allocator, 109);
    defer prime_getter.deinit(std.testing.allocator);

    try std.testing.expect(prime_getter.isPrime(109));
    try std.testing.expect(prime_getter.isPrime(7));
    try std.testing.expect(prime_getter.isPrime(11));
    try std.testing.expect(!prime_getter.isPrime(10));

    try std.testing.expectEqual(2, prime_getter.nextRestricted(1, 109));
    try std.testing.expectEqual(3, prime_getter.nextRestricted(2, 109));
    try std.testing.expectEqual(5, prime_getter.nextRestricted(3, 109));
    try std.testing.expectEqual(5, prime_getter.nextRestricted(4, 109));
    try std.testing.expectEqual(7, prime_getter.nextRestricted(5, 109));
    try std.testing.expectEqual(7, prime_getter.nextRestricted(6, 109));
    try std.testing.expectEqual(11, prime_getter.nextRestricted(7, 109));
    try std.testing.expectEqual(109, prime_getter.nextRestricted(108, 110));
}
