const std = @import("std");
const wav = @import("wav.zig");
const dft = @import("dft.zig");
const plotting = @import("plotting.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        std.debug.assert(gpa.deinit() == .ok);
    }

    const fnames = [_][]const u8{
        "test_music/audiocheck.net_hdsweep_1Hz_44000Hz_-3dBFS_30s",
        "test_music/Free_Test_Data_10MB_WAV",
        "test_music/mono16_sinewave",
        "test_music/stereo16_mixture",
        "test_music/stereo16_sine_cosine",
        "test_music/stereo16_sine",
        "test_music/wavTones.com.unregistred.rect_-6dBFS_5samples",
        "test_music/wavTones.com.unregistred.rect_-10dBFS_12samples",
    };

    inline for (fnames) |fname| {
        var wave = wav.WaveFile.init(allocator);
        defer wave.deinit();

        wave.decodeFile(fname ++ ".wav") catch |err| {
            std.log.err("{}", .{err});
            std.os.exit(1);
        };
        wave.printHeader();
        const samples = try wave.getSampleSliceAlloc(allocator, 1, 1000, 1);
        defer allocator.free(samples);

        const transformed_samples = try allocator.alloc(f32, 256);
        defer allocator.free(transformed_samples);
        
        dft.fft(samples, 1, transformed_samples, 256);
        
        std.log.info("{any}", .{samples[0..100]});
        std.log.info("{any}", .{transformed_samples[0..100]});
    }
}
