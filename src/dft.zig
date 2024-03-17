const std = @import("std");
const math = std.math;
const testing = std.testing;

const c32 = math.Complex(f32);

pub fn fft(
    input: []i32,
    stride: usize,
    out_buf: []c32,
    n: usize,
) void {
    if (n == 1) {
        out_buf[0] = c32.init(@floatFromInt(input[0]), 0);
        return;
    }

    fft(input, 2 * stride, out_buf, n / 2);
    fft(input[0 + stride ..], 2 * stride, out_buf[0 + n / 2 ..], n / 2);

    for (0..n / 2) |k| {
        const t: f32 = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(n));
        const v = c32.init(math.cos(2 * math.pi * t), math.sin(2 * math.pi * t)).mul(out_buf[k + n / 2]);
        const e = out_buf[k];
        out_buf[k] = e.add(v);
        out_buf[k + n / 2] = e.sub(v);
    }
}

test "dft_test" {
    var inputs = [_]i32{ 1, 1, 1, 1, 0, 0, 0, 0 };

    const outputs = try testing.allocator.alloc(c32, inputs.len);
    defer testing.allocator.free(outputs);

    fft(&inputs, 1, outputs, inputs.len);

    std.debug.print("{any}\n", .{inputs});
    std.debug.print("{any}\n", .{outputs});
}
