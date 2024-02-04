const std = @import("std");
const testing = std.testing;
const plotting = @import("plotting.zig");

pub const WaveHeader = struct {
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
};

pub fn MonoAudio(comptime T: type) type {
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

pub fn StereoAudio(comptime T: type) type {
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

pub const WaveData = union(enum) {
    MonoAudio8: MonoAudio(i8),
    StereoAudio8: StereoAudio(i8),
    MonoAudio16: MonoAudio(i16),
    StereoAudio16: StereoAudio(i16),
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
            std.debug.print("{s}: {any}\n", .{ field.name, @as(field.type, @field(this.header.*, field.name)) });
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
};

test "Wave file header read" {
    var wave = try WaveFile.init(testing.allocator);
    defer wave.deinit();

    wave.decode("test_music/stereo16_mixture.wav") catch |err| {
        std.log.err("{}", .{err});
        std.os.exit(1);
    };
    wave.printHeader();

    var plot = plotting.Plot(i16).init(testing.allocator);
    defer plot.deinit();

    const len = 100;

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
        try time_stamps.append(@as(i16, @intCast(@as(u8, @truncate(i)))));
    }

    try plot.addPlot(time_stamps.items[0..], wave.wave_data.StereoAudio16.channel1.items[0..], "Channel 1");
    try plot.addPlot(time_stamps.items[0..], wave.wave_data.StereoAudio16.channel2.items[0..], "Channel 2");

    try plot.saveFig("testing3.png", .PNG);
}
