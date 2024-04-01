const std = @import("std");
const math = std.math;
const mem = std.mem;
const log = std.log.scoped(.dft);
const testing = std.testing;

const c32 = math.Complex(f32);

pub const Spectogram = struct {
    const Self = @This();

    map: std.AutoArrayHashMapUnmanaged(i32, []f32),
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .map = std.AutoArrayHashMapUnmanaged(i32, []f32){},
            .allocator = allocator,
        };
    }

    pub fn addValue(self: *Self, key: i32, value: []f32) !void {
        try self.map.putNoClobber(self.allocator, key, value);
    }

    pub fn saveSpectogram(self: *Self, fname: []u8) !void {
        var file = std.fs.cwd().openFile(fname, .{}) catch |err|
            switch (err) {
            error.FileNotFound => try std.fs.cwd().createFile(fname, .{}),
            else => return err,
        };

        defer file.close();

        var w = file.writer();
        var it = self.map.iterator();
        while (it.next()) |entry| {
            try w.print("{d}\t{any}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    pub fn deinit(self: *Self) void {
        while (self.map.popOrNull()) |entry| {
            self.allocator.free(entry.value);
        }

        self.map.deinit(self.allocator);
    }
};

pub fn fft(
    input: []const f32,
    stride: usize,
    out_buf: []c32,
    n: usize,
) void {
    if (n == 1) {
        out_buf[0] = c32.init(input[0], 0);
        return;
    }

    fft(input, 2 * stride, out_buf, n / 2);
    fft(input[0 + stride ..], 2 * stride, out_buf[0 + n / 2 ..], n / 2);

    for (0..n / 2) |k| {
        const t: f32 = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(n));
        const v = c32.init(
            math.cos(2 * math.pi * t),
            math.sin(2 * math.pi * t),
        ).mul(out_buf[k + n / 2]);
        const e = out_buf[k];
        out_buf[k] = e.add(v);
        out_buf[k + n / 2] = e.sub(v);
    }
}

pub fn windowedFFT(
    allocator: std.mem.Allocator,
    input: []i32,
    fft_size: usize,
) !Spectogram {
    const size = if (fft_size > input.len) input.len else fft_size;
    var iterator = mem.window(i32, input, size, size / 2);

    // Init hashmap for spectogram
    var ret_map = Spectogram.init(allocator);

    var i: isize = 0;

    const tmp_buffer = try allocator.alloc(c32, size);
    defer allocator.free(tmp_buffer);
    @memset(tmp_buffer, c32.init(0.0, 0.0));

    var tmp_input = try allocator.alloc(f32, size);
    defer allocator.free(tmp_input);
    @memset(tmp_input, 0.0);

    while (iterator.next()) |window| {
        // Apply the Hann window function
        for (window, 0..) |w, j| {
            const hann = 0.5 - 0.5 * math.cos(
                2.0 * math.pi * @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(size - 1)),
            );
            tmp_input[j] = @as(f32, @floatFromInt(w)) * hann;
        }

        fft(tmp_input, 1, tmp_buffer, size);

        var data = try allocator.alloc(f32, size);
        for (0.., tmp_buffer) |j, fft_data| {
            data[j] = fft_data.magnitude();
        }

        try ret_map.addValue(@as(i32, @truncate(i)), data);
        @memset(tmp_buffer, c32.init(0.0, 0.0));
        i += 1;
    }

    return ret_map;
}

test "dft_test" {
    var inputs = [_]i32{ 1, 1, 1, 1, 0, 0, 0, 0 };

    const outputs = try testing.allocator.alloc(c32, inputs.len);
    defer testing.allocator.free(outputs);

    fft(&inputs, 1, outputs, inputs.len);

    std.debug.print("{any}\n", .{inputs});
    std.debug.print("{any}\n", .{outputs});
}

test "windowed_fft test" {
    var inputs = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };

    var spect = try windowedFFT(testing.allocator, &inputs, 5);
    defer spect.deinit();

    var it = spect.map.iterator();
    while (it.next()) |entry| {
        std.debug.print("{d}: {any}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}

// test "files_fft test" {
//     const wave_files = @import("wav.zig");

//     var count: usize = 0;
//     const dir_path = try std.fs.realpathAlloc(testing.allocator, "/home/thetrashed/Programming/Personal/music_genre_ai/test_music/Data/genres_original");

//     defer testing.allocator.free(dir_path);

//     var directories = try std.fs.openDirAbsolute(
//         dir_path,
//         .{ .iterate = true },
//     );
//     defer directories.close();
//     var d_it = directories.iterate();

//     while (try d_it.next()) |directory| {
//         if (directory.kind == .directory) {
//             const new_dir = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ dir_path, directory.name });
//             defer testing.allocator.free(new_dir);

//             var files = try std.fs.openDirAbsolute(new_dir, .{ .iterate = true });
//             defer files.close();
//             std.debug.print("Processing: {s}\n", .{new_dir});

//             var f_it = files.iterate();
//             while (try f_it.next()) |file| {
//                 if (!std.mem.eql(u8, file.name[file.name.len - 4 .. file.name.len], ".wav")) {
//                     std.debug.print("{s}\n", .{file.name});
//                     continue;
//                 }
//                 const file_path = try std.fmt.allocPrint(testing.allocator, "{s}/{s}/{s}", .{ dir_path, directory.name, file.name });
//                 defer testing.allocator.free(file_path);

//                 std.log.warn("Processing {s}", .{file_path});
//                 var wave = wave_files.WaveFile.init(testing.allocator);
//                 defer wave.deinit();

//                 wave.decodeFile(file_path) catch |err| {
//                     std.log.err("{}", .{err});
//                     return;
//                 };

//                 const x = try wave.getAllDataSliceAlloc(testing.allocator, 2);
//                 defer testing.allocator.free(x);

//                 const out = try testing.allocator.alloc(c32, x.len);
//                 defer testing.allocator.free(out);

//                 fft(x, 1, out, x.len);
//                 count += 1;
//             }

//         }
//     }

//     std.debug.print("{d} files processed\n", .{count});
// }