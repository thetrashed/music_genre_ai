const std = @import("std");
const wav = @import("wav.zig");
const dft = @import("dft.zig");
const log = std.log.scoped(.main);

const c32 = std.math.Complex(f32);

const fft_size = 1024;
const dir_path = "test_music/Data/genres_original";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        std.debug.assert(gpa.deinit() == .ok);
    }

    var directories = std.fs.cwd().openDir(
        dir_path,
        .{ .iterate = true },
    ) catch |err| {
        log.err("{s}: {}", .{ dir_path, err });
        return err;
    };
    defer directories.close();

    var spectograms: [1000]dft.Spectogram = undefined;
    defer {
        for (&spectograms) |*spectogram| {
            spectogram.deinit();
        }
    }

    var d_it = directories.iterate();
    var spect_index: usize = 0;
    while (try d_it.next()) |directory| {
        if (directory.kind == .directory) {
            const new_dir = try std.fmt.allocPrint(
                allocator,
                "{s}/{s}",
                .{ dir_path, directory.name },
            );
            defer allocator.free(new_dir);

            var files = std.fs.cwd().openDir(new_dir, .{ .iterate = true }) catch |err| {
                log.err("{s}: {}", .{ new_dir, err });
                return err;
            };
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
                    log.err("{s}: {}", .{ file_path, err });
                    return err;
                };

                const samples = try wave.getAllDataSliceAlloc(allocator, 2);
                defer allocator.free(samples);

                spectograms[spect_index] = try dft.windowedFFT(allocator, samples, fft_size);
                const spect_fname = try std.fmt.allocPrint(
                    allocator,
                    "{s}/{s}/{s}/{s}",
                    .{ dir_path, "../spectograms", directory.name, file.name[0 .. file.name.len - 4] },
                    wave.header.?.sample_rate,
                );
                defer allocator.free(spect_fname);

                spectograms[spect_index].saveSpectogram(spect_fname) catch |err| {
                    log.err("{s}: {}", .{ spect_fname, err });
                    return err;
                };
                spect_index += 1;
            }
        }
    }
}
