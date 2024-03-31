const std = @import("std");
const wav = @import("wav.zig");
const dft = @import("dft.zig");
const log = std.log.scoped(.main);
const plotting = @import("plotting.zig");

const c32 = std.math.Complex(f32);

const fft_size = std.math.pow(usize, 2, 13);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        std.debug.assert(gpa.deinit() == .ok);
    }

    const dir_path = "test_music/Data/genres_original";

    var directories = try std.fs.cwd().openDir(
        dir_path,
        .{ .iterate = true },
    );
    defer directories.close();

    var spectograms = std.ArrayList(dft.Spectogram).init(allocator);
    defer {
        while (true) {
            var spectogram = spectograms.popOrNull() orelse break;
            spectogram.deinit();
        }
        spectograms.deinit();
    }

    var d_it = directories.iterate();
    while (try d_it.next()) |directory| {
        if (directory.kind == .directory) {
            const new_dir = try std.fmt.allocPrint(
                allocator,
                "{s}/{s}",
                .{ dir_path, directory.name },
            );
            defer allocator.free(new_dir);

            var files = try std.fs.cwd().openDir(new_dir, .{ .iterate = true });
            defer files.close();
            log.info("Processing: {s}", .{new_dir});

            var f_it = files.iterate();
            while (try f_it.next()) |file| {
                if (!std.mem.eql(
                    u8,
                    file.name[file.name.len - 4 .. file.name.len],
                    ".wav",
                )) {
                    continue;
                }
                const file_path = try std.fmt.allocPrint(
                    allocator,
                    "{s}/{s}/{s}",
                    .{ dir_path, directory.name, file.name },
                );
                defer allocator.free(file_path);

                var wave = wav.WaveFile.init(allocator);
                defer wave.deinit();

                wave.decodeFile(file_path) catch |err| {
                    log.err("{}", .{err});
                    return;
                };

                const samples = try wave.getAllDataSliceAlloc(allocator, 2);
                defer allocator.free(samples);

                try spectograms.append(try dft.windowedFFT(allocator, samples, fft_size));
            }
        }
    }
}
