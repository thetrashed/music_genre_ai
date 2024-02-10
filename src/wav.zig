const std = @import("std");
const testing = std.testing;
const plotting = @import("plotting.zig");

const WaveHeader = struct {
    const This = @This();

    magic: [4]u8,
    chunk_size: u32,
    format: [4]u8,

    fmt_magic: [4]u8,
    fmt_size: u32,
    audio_format: u16,
    channels: u16,
    sample_rate: u32,
    byte_rate: u32,
    block_align: u16,
    bits_per_sample: u16,

    data_magic: [4]u8,
    data_size: u32,

    pub fn reset(this: *This) void {
        this.magic = [_]u8{0} ** 4;
        this.format = [_]u8{0} ** 4;
        this.fmt_magic = [_]u8{0} ** 4;
        this.data_magic = [_]u8{0} ** 4;

        this.chunk_size = 0;
        this.fmt_size = 0;
        this.audio_format = 0;
        this.channels = 0;
        this.sample_rate = 0;
        this.byte_rate = 0;
        this.block_align = 0;
        this.bits_per_sample = 0;
    }
};

const WaveData = struct {
    const This = @This();

    channel1: ?std.ArrayList(i32),
    channel2: ?std.ArrayList(i32),

    pub fn init(allocator: std.mem.Allocator, channels: u32) !This {
        return switch (channels) {
            1 => .{
                .channel1 = std.ArrayList(i32).init(allocator),
                .channel2 = null,
            },
            2 => .{
                .channel1 = std.ArrayList(i32).init(allocator),
                .channel2 = std.ArrayList(i32).init(allocator),
            },
            else => error.NotSupportedOrImplemented,
        };
    }

    pub fn deinit(this: This) void {
        if (this.channel1) |channel| {
            channel.deinit();
        }
        if (this.channel2) |channel| {
            channel.deinit();
        }
    }
};

pub const WaveFile = struct {
    const This = @This();

    header: ?*WaveHeader,
    wave_data: ?WaveData,
    file: ?std.fs.File,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !This {
        return .{
            .header = null,
            .wave_data = null,
            .file = null,
            .allocator = allocator,
        };
    }

    pub fn decode(this: *This, fname: []const u8) !void {
        std.log.warn("Finding file: {s}", .{fname});

        const file_path = try std.fs.realpathAlloc(this.allocator, fname);
        defer this.allocator.free(file_path);

        this.file = try std.fs.openFileAbsolute(file_path, .{});
        errdefer {
            this.file.?.close();
            this.header.?.reset();
            if (this.wave_data) |wave_data| {
                wave_data.deinit();
            }
            this.allocator = this.allocator;
            this.file = null;
        }

        const reader = this.file.?.reader();

        this.header = try this.allocator.create(WaveHeader);
        this.header.?.magic = try reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &this.header.?.magic, "RIFF")) {
            return error.InvalidID;
        }
        this.header.?.chunk_size = try reader.readInt(u32, .little);

        this.header.?.format = try reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &this.header.?.format, "WAVE")) {
            return error.InvalidID;
        }

        this.header.?.fmt_magic = try reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &this.header.?.fmt_magic, "fmt ")) {
            return error.InvalidID;
        }
        this.header.?.fmt_size = try reader.readInt(u32, .little);
        this.header.?.audio_format = try reader.readInt(u16, .little);
        this.header.?.channels = try reader.readInt(u16, .little);
        this.header.?.sample_rate = try reader.readInt(u32, .little);
        this.header.?.byte_rate = try reader.readInt(u32, .little);
        this.header.?.block_align = try reader.readInt(u16, .little);
        this.header.?.bits_per_sample = try reader.readInt(u16, .little);

        this.header.?.data_magic = try reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &this.header.?.data_magic, "data")) {
            return error.InvalidID;
        }

        this.header.?.data_size = try reader.readInt(u32, .little);
        this.wave_data = try WaveData.init(this.allocator, this.header.?.channels);
    }

    pub fn deinit(this: This) void {
        if (this.header) |header| {
            this.allocator.destroy(header);
        }
        if (this.wave_data) |wave_data| {
            wave_data.deinit();
        }
        if (this.file) |file| {
            file.close();
        }
    }

    pub fn printHeader(this: This) void {
        inline for (std.meta.fields(@TypeOf(this.header.?.*))) |field| {
            std.log.warn("{s}: {any}", .{ field.name, @as(field.type, @field(this.header.?.*, field.name)) });
        }
    }

    /// Reads a sample from the wave file.
    /// - Reads 1 sample from a mono audio file.
    /// - Reads 1 sample for each channel for a stereo audio file.
    pub fn readSample(this: *This) !void {
        const reader = this.file.?.reader();

        switch (this.header.?.channels) {
            1 => switch (this.header.?.bits_per_sample) {
                8 => try this.wave_data.?.channel1.?.append(@intCast(try reader.readInt(u8, .little))),
                16 => try this.wave_data.?.channel1.?.append(@intCast(try reader.readInt(i16, .little))),
                else => return error.NotSupportedOrImplemented,
            },
            2 => switch (this.header.?.bits_per_sample) {
                8 => {
                    try this.wave_data.?.channel1.?.append(@intCast(try reader.readInt(u8, .little)));
                    try this.wave_data.?.channel2.?.append(@intCast(try reader.readInt(u8, .little)));
                },
                16 => {
                    try this.wave_data.?.channel1.?.append(@intCast(try reader.readInt(i16, .little)));
                    try this.wave_data.?.channel2.?.append(@intCast(try reader.readInt(i16, .little)));
                },
                else => return error.NotSupportedOrImplemented,
            },
            else => return error.NotSupportedOrImplemented,
        }
    }

    pub fn getSampleSlice(this: This, start_sample: usize, size: usize, channel: ?usize) ![]i32 {
        const ch = channel orelse 1;

        switch (ch) {
            1 => return this.wave_data.?.channel1.?.items[start_sample .. start_sample + size],
            2 => {
                if (this.header.?.channels == 1) {
                    return error.AudioNotStereo;
                }
                return this.wave_data.?.channel2.?.items[start_sample .. start_sample + size];
            },
            else => return error.NotSupportedOrImplemented,
        }
    }
};

test "Wave file header read" {
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
        var wave = try WaveFile.init(testing.allocator);
        defer wave.deinit();

        wave.decode(fname ++ ".wav") catch |err| {
            std.log.err("{}", .{err});
            std.os.exit(1);
        };
        wave.printHeader();

        var plot = plotting.Plot(i32).init(testing.allocator);
        defer plot.deinit();

        const len = 88200;

        var time_stamps = std.ArrayList(i32).init(testing.allocator);
        defer time_stamps.deinit();

        for (0..len) |i| {
            wave.readSample() catch |err| {
                switch (err) {
                    error.EndOfStream => break,
                    else => {
                        std.log.err("{}", .{err});
                        return err;
                    },
                }
            };
            try time_stamps.append(@intCast(@as(u31, @truncate(i))));
        }

        try plot.addPlot(time_stamps.items[0..10000], try wave.getSampleSlice(0, 10000, 1), "Channel 1");
        if (wave.header.?.channels == 2) {
            try plot.addPlot(time_stamps.items[0..10000], try wave.getSampleSlice(0, 10000, 2), "Channel 2");
        }

        try plot.saveFig(fname ++ ".png", .PNG);
    }
}
