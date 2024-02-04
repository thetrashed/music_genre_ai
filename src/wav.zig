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

    pub fn init(allocator: std.mem.Allocator) !This {
        const header = try allocator.create(WaveHeader);

        return .{
            .header = header,
            .wave_data = undefined,
            .allocator = allocator,
        };
    }

    pub fn decode(this: *This, fname: []const u8) !void {
        std.log.warn("Finding file: {s}", .{fname});
        const file_path = try std.fs.realpathAlloc(this.allocator, fname);
        defer this.allocator.free(file_path);

        const file = try std.fs.openFileAbsolute(file_path, .{});
        defer file.close();

        const reader = file.reader();

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
        while (this.readSample(reader)) {} else |err| {
            switch (err) {
                error.EndOfStream => {},
                else => return err,
            }
        }
    }

    pub fn deinit(this: This) void {
        this.allocator.destroy(this.header);
        switch (this.wave_data) {
            WaveData.MonoAudio8 => |*wave| {
                wave.data.deinit();
            },
            WaveData.MonoAudio16 => |*wave| {
                wave.data.deinit();
            },
            WaveData.StereoAudio8 => |*wave| {
                wave.channel1.deinit();
                wave.channel2.deinit();
            },
            WaveData.StereoAudio16 => |*wave| {
                wave.channel1.deinit();
                wave.channel2.deinit();
            },
        }
        // this.wave_data.deinit();
    }

    pub fn printHeader(this: This) void {
        inline for (std.meta.fields(@TypeOf(this.header.*))) |field| {
            std.debug.print("{s}: {any}\n", .{ field.name, @as(field.type, @field(this.header.*, field.name)) });
        }
    }

    fn readSample(this: *This, reader: anytype) !void {
        switch (this.wave_data) {
            WaveData.MonoAudio8 => |*wave| {
                try wave.data.append(try reader.readInt(i8, .little));
            },
            WaveData.MonoAudio16 => |*wave| {
                try wave.data.append(try reader.readInt(i16, .little));
            },
            WaveData.StereoAudio8 => |*wave| {
                try wave.channel1.append(try reader.readInt(i8, .little));
                try wave.channel2.append(try reader.readInt(i8, .little));
            },
            WaveData.StereoAudio16 => |*wave| {
                try wave.channel1.append(try reader.readInt(i16, .little));
                try wave.channel2.append(try reader.readInt(i16, .little));
            },
        }
    }
};

test "Wave file header read" {
    var wave = try WaveFile.init(testing.allocator);
    defer wave.deinit();

    wave.decode("test_music/mono16_sinewave.wav") catch |err| {
        std.log.err("{}", .{err});
        std.os.exit(1);
    };
    wave.printHeader();

    var plot = plotting.Plot(f32).init(testing.allocator);
    defer plot.deinit();

    const len = wave.wave_data.StereoAudio16.channel1.items.len;
    var ys = std.ArrayList(f32).init(testing.allocator);
    var time_stamps = std.ArrayList(f32).init(testing.allocator);
    defer ys.deinit();
    defer time_stamps.deinit();
    for (0..len) |i| {
        try time_stamps.append(@as(f32, @floatFromInt(i)) / 44100.00);
        try ys.append(@as(f32, @floatFromInt(wave.wave_data.StereoAudio16.channel1.items[i])));
    }

    try plot.addPlot(time_stamps.items[0..100], ys.items[0..100], null);
    try plot.saveFig("testing.png", .PNG);
}
