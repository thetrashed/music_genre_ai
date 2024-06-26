const std = @import("std");
const math = @import("math");

const wav = @import("wav.zig");
const dft = @import("dft.zig");
const nn = @import("neural_network.zig");

pub const std_options = .{
    .log_level = .info,
};
const log = std.log.scoped(.main);

const input_samples = 20;
const num_files = 1000;
const fft_size = 512;

const model_file = "neural_network.model";
const dir_path = "test_music/Data/genres_original";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        std.debug.assert(gpa.deinit() == .ok);
    }

    // Store the expected outputs in a two dimensional array
    const expected_outputs: [][]f32 = try allocator.alloc([]f32, num_files);
    defer {
        for (expected_outputs) |outputs| {
            allocator.free(outputs);
        }
        allocator.free(expected_outputs);
    }

    for (0..expected_outputs.len) |i| {
        expected_outputs[i] = try allocator.alloc(f32, 10);
        @memset(expected_outputs[i], 0.0);
        expected_outputs[i][i / 100] = 1.0;
    }

    // Get and open the directory in which the test data is stored
    var directories = std.fs.cwd().openDir(
        dir_path,
        .{ .iterate = true },
    ) catch |err| {
        log.err("{s}: {}", .{ dir_path, err });
        return err;
    };
    defer directories.close();

    // Allocate space for the spectograms
    const spectograms: []dft.Spectogram = try allocator.alloc(dft.Spectogram, num_files);
    defer allocator.free(spectograms);
    errdefer {
        for (spectograms) |*spectogram| {
            spectogram.deinit();
        }
    }

    // Allocate space for the labels (technically the label mappings)
    const labels: [][]u8 = try allocator.alloc([]u8, 10);
    defer allocator.free(labels);

    // Obtain the spectograms of the audio files and the labels for the outputs of
    // the neural network
    try obtainSpectogramsAndLabels(allocator, &directories, spectograms, labels);

    // Normalise the spectograms and obtain a flattened array for each spectogram
    log.info("Flattening and normalising data", .{});
    var flattened_data: [][]f32 = try allocator.alloc([]f32, spectograms.len);
    defer {
        for (flattened_data) |data| {
            allocator.free(data);
        }
        allocator.free(flattened_data);
    }

    for (spectograms, 0..) |*spectogram, i| {
        // Normalise the spectrum
        spectogram.normalise();

        // The flattening part
        var j: usize = 0;
        var spec_it = spectogram.map.iterator();
        flattened_data[i] = try allocator.alloc(f32, input_samples * fft_size);
        while (j < input_samples) : (j += 1) {
            const val = (spec_it.next() orelse break).value_ptr.*;

            for (val) |v| {
                flattened_data[i][j] = v;
            }
        }
    }

    // Deinit the spectograms
    for (spectograms) |*spectogram| {
        spectogram.deinit();
    }

    // Set up the neural network architecture
    // 3 layers -> 1 hidden, 1 input and 1 output layer
    // Since the input arrays are "input_samples" * "fft_size" long, the input layer has that many nodes.
    var arch_type = [_]usize{ input_samples * fft_size, 2 * input_samples * fft_size, 2 * input_samples * fft_size, 10 };
    const architecture = try nn.createArchitecture(allocator, 4, &arch_type);
    defer nn.destroyArchitecture(allocator, architecture);

    // Learning rate
    const alpha = 0.15;

    // Iterate for 20000 epochs
    log.info("Iterating", .{});
    var epoch: usize = 0;
    while (epoch < 20000) : (epoch += 1) {
        log.info("Epoch {d}", .{epoch});
        for (0..flattened_data.len) |i| {
            nn.feedInput(&architecture[0], flattened_data, i);
            nn.forwardPropagation(architecture);
            nn.backwardPropagation(architecture, expected_outputs, i);
            nn.updateWeights(architecture, alpha);
        }
    }

    // Write the model weights (actually the neurons) to a file
    var mf_ptr = std.fs.cwd().openFile(model_file, .{}) catch |err| switch (err) {
        error.FileNotFound => try std.fs.cwd().createFile(model_file, .{}),
        else => return err,
    };
    defer mf_ptr.close();

    const writer = mf_ptr.writer();
    for (architecture) |layer| {
        for (layer.neu) |neuron| {
            try neuron.writeToFile(writer);
        }
    }
}

// Looping over the directories and related stuff, including reading the actual audio
// files and obtaining the samples and the spectra.
fn obtainSpectogramsAndLabels(
    allocator: std.mem.Allocator,
    directories: *std.fs.Dir,
    spectograms: []dft.Spectogram,
    labels: [][]const u8,
) !void {
    var d_it = directories.iterate();
    var spect_index: usize = 0;
    var lab_index: usize = 0;
    while (try d_it.next()) |directory| {
        if (directory.kind == .directory) {
            const new_dir = try std.fmt.allocPrint(
                allocator,
                "{s}/{s}",
                .{ dir_path, directory.name },
            );
            defer allocator.free(new_dir);
            labels[lab_index] = directory.name;
            lab_index += 1;

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

                const samples = try wave.getAllDataSliceAlloc(allocator, 1);
                defer allocator.free(samples);

                spectograms[spect_index] = try dft.windowedFFT(
                    allocator,
                    samples,
                    fft_size,
                    wave.header.?.sample_rate,
                );
                spect_index += 1;
            }
        }
    }
}
