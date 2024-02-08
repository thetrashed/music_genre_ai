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

fn MonoAudio(comptime T: type) type {
    return struct {
        const This = @This();

        data: std.ArrayList(T),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) This {
            return .{
                .data = std.ArrayList(T).init(allocator),
                .allocator = allocator,
            };
        }
    };
}

fn StereoAudio(comptime T: type) type {
    return struct {
        const This = @This();

        channel1: std.ArrayList(T),
        channel2: std.ArrayList(T),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) This {
            return .{
                .channel1 = std.ArrayList(T).init(allocator),
                .channel2 = std.ArrayList(T).init(allocator),
                .allocator = allocator,
            };
        }
    };
}

const WaveData = union(enum) {
    MonoAudio8: MonoAudio(i8),
    StereoAudio8: StereoAudio(i8),
    MonoAudio16: MonoAudio(i16),
    StereoAudio16: StereoAudio(i16),
};

const WaveDataTypes = union(enum) {
    i8: i8,
    i16: i16,
};

pub const WaveFile = struct {
    const This = @This();

    header: *WaveHeader,
    wave_data: WaveData,
    allocator: std.mem.Allocator,
    file_pointer: ?std.fs.File,
    file_position: usize,

    pub fn init(allocator: std.mem.Allocator) !This {
        const header = try allocator.create(WaveHeader);

        return .{
            .header = header,
            .wave_data = undefined,
            .allocator = allocator,
            .file_pointer = null,
            .file_position = 0,
        };
    }

    pub fn decode(this: *This, fname: []const u8) !void {
        std.log.warn("Finding file: {s}", .{fname});
        const file_path = try std.fs.realpathAlloc(this.allocator, fname);
        defer this.allocator.free(file_path);

        this.file_pointer = try std.fs.openFileAbsolute(file_path, .{});
        errdefer {
            this.file_pointer.?.close();
            this.header.reset();
            this.wave_data = undefined;
            this.allocator = this.allocator;
            this.file_pointer = null;
            this.file_position = 0;
        }

        const reader = this.file_pointer.?.reader();

        this.header.magic = try reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &this.header.magic, "RIFF")) {
            return error.InvalidID;
        }
        this.header.chunk_size = try reader.readInt(u32, .little);

        this.header.format = try reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &this.header.format, "WAVE")) {
            return error.InvalidID;
        }

        this.header.fmt_magic = try reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &this.header.fmt_magic, "fmt ")) {
            return error.InvalidID;
        }
        this.header.fmt_size = try reader.readInt(u32, .little);
        this.header.audio_format = try reader.readInt(u16, .little);
        this.header.channels = try reader.readInt(u16, .little);
        this.header.sample_rate = try reader.readInt(u32, .little);
        this.header.byte_rate = try reader.readInt(u32, .little);
        this.header.block_align = try reader.readInt(u16, .little);
        this.header.bits_per_sample = try reader.readInt(u16, .little);

        this.header.data_magic = try reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &this.header.data_magic, "data")) {
            return error.InvalidID;
        }

        this.header.data_size = try reader.readInt(u32, .little);
        switch (this.header.channels) {
            1 => {
                switch (this.header.bits_per_sample) {
                    8 => this.wave_data = WaveData{ .MonoAudio8 = MonoAudio(i8).init(this.allocator) },
                    16 => this.wave_data = WaveData{ .MonoAudio16 = MonoAudio(i16).init(this.allocator) },
                    else => return error.NotImplementedOrSupported,
                }
            },
            2 => {
                switch (this.header.bits_per_sample) {
                    8 => this.wave_data = WaveData{ .StereoAudio8 = StereoAudio(i8).init(this.allocator) },
                    16 => this.wave_data = WaveData{ .StereoAudio16 = StereoAudio(i16).init(this.allocator) },
                    else => return error.NotImplementedOrSupported,
                }
            },
            else => return error.NotImplementedOrSupported,
        }
        this.file_position = 44;
    }

    pub fn deinit(this: This) void {
        this.allocator.destroy(this.header);
        switch (this.wave_data) {
            WaveData.MonoAudio8 => |*wave_data| {
                wave_data.data.deinit();
            },
            WaveData.MonoAudio16 => |*wave_data| {
                wave_data.data.deinit();
            },
            WaveData.StereoAudio8 => |*wave_data| {
                wave_data.channel1.deinit();
                wave_data.channel2.deinit();
            },
            WaveData.StereoAudio16 => |*wave_data| {
                wave_data.channel1.deinit();
                wave_data.channel2.deinit();
            },
        }
        this.file_pointer.?.close();
        // this.wave_data.deinit();
    }

    pub fn printHeader(this: This) void {
        inline for (std.meta.fields(@TypeOf(this.header.*))) |field| {
            std.log.warn("{s}: {any}", .{ field.name, @as(field.type, @field(this.header.*, field.name)) });
        }
    }

    /// Reads a sample from the wave file.
    /// - Reads 1 sample from a mono audio file.
    /// - Reads 1 sample for each channel for a stereo audio file.
    pub fn readSample(this: *This) !void {
        try this.file_pointer.?.seekTo(this.file_position);
        const reader = this.file_pointer.?.reader();

        switch (this.wave_data) {
            WaveData.MonoAudio8 => |*wave_data| {
                try wave_data.data.append(try reader.readInt(i8, .little));
                this.file_position += 1;
            },
            WaveData.MonoAudio16 => |*wave_data| {
                try wave_data.data.append(try reader.readInt(i16, .little));
                this.file_position += 2;
            },
            WaveData.StereoAudio8 => |*wave_data| {
                try wave_data.channel1.append(try reader.readInt(i8, .little));
                try wave_data.channel2.append(try reader.readInt(i8, .little));
                this.file_position += 2;
            },
            WaveData.StereoAudio16 => |*wave_data| {
                try wave_data.channel1.append(try reader.readInt(i16, .little));
                try wave_data.channel2.append(try reader.readInt(i16, .little));
                this.file_position += 4;
            },
        }
    }

    pub fn get8BitSampleSlice(this: This, start_sample: usize, size: ?usize, channel: ?u16) ![]i8 {
        switch (this.wave_data) {
            WaveData.MonoAudio8 => |*wave_data| {
                const tmpsize = size orelse wave_data.data.items.len - start_sample;
                return wave_data.data.items[start_sample .. start_sample + tmpsize];
            },
            WaveData.MonoAudio16 => return error.AudioNot8Bit,
            WaveData.StereoAudio8 => |*wave_data| {
                switch (channel orelse 1) {
                    1 => {
                        const tmpsize = size orelse wave_data.channel1.items.len - start_sample;
                        return wave_data.channel1.items[start_sample .. start_sample + tmpsize];
                    },
                    2 => {
                        const tmpsize = size orelse wave_data.channel2.items.len - start_sample;
                        return wave_data.channel2.items[start_sample .. start_sample + tmpsize];
                    },
                    else => return error.IncorrectChannel,
                }
            },

            WaveData.StereoAudio16 => return error.AudioNot8Bit,
        }
    }

    pub fn get16BitSampleSlice(this: This, start_sample: usize, size: ?usize, channel: ?u16) ![]i16 {
        switch (this.wave_data) {
            WaveData.MonoAudio8 => return error.AudioNot16Bit,
            WaveData.MonoAudio16 => |*wave_data| {
                const tmpsize = size orelse wave_data.data.items.len - start_sample;
                return wave_data.data.items[start_sample .. start_sample + tmpsize];
            },
            WaveData.StereoAudio8 => return error.AudioNot16Bit,
            WaveData.StereoAudio16 => |*wave_data| {
                switch (channel orelse 1) {
                    1 => {
                        const tmpsize = size orelse wave_data.channel1.items.len - start_sample;
                        return wave_data.channel1.items[start_sample .. start_sample + tmpsize];
                    },
                    2 => {
                        const tmpsize = size orelse wave_data.channel2.items.len - start_sample;
                        return wave_data.channel2.items[start_sample .. start_sample + tmpsize];
                    },
                    else => return error.IncorrectChannel,
                }
            },
        }
    }
};

test "Wave file header read" {
    const fnames = [_][]const u8{
        "test_music/stereo16_sine",
        "test_music/stereo16_sine_cosine",
       "test_music/stereo16_mixture",
        "test_music/mono16_sinewave",
    };

    inline for (fnames) |fname| {
        var wave = try WaveFile.init(testing.allocator);
        defer wave.deinit();

        wave.decode(fname ++ ".wav") catch |err| {
            std.log.err("{}", .{err});
            std.os.exit(1);
        };
        wave.printHeader();

        var plot = plotting.Plot(i16).init(testing.allocator);
        defer plot.deinit();

        const len = 88200;

        var time_stamps = std.ArrayList(i16).init(testing.allocator);
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
            try time_stamps.append(@intCast(@as(u15, @truncate(i))));
        }

        try plot.addPlot(time_stamps.items[0..1000], try wave.get16BitSampleSlice(0, 1000, 1), "Channel 1");
        try plot.addPlot(time_stamps.items[0..1000], try wave.get16BitSampleSlice(0, 1000, 2), "Channel 2");

        try plot.saveFig(fname ++ ".png", .PNG);
    }
}
