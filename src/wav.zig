const std = @import("std");
const testing = std.testing;

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

const WaveData = enum {
    u8,
    u16,
    i8,
    i16,
};

pub const WaveFile = struct {
    const This = @This();

    header: *WaveHeader,
    wave_data: ?std.ArrayList(WaveData),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !This {
        const header = try allocator.create(WaveHeader);

        return .{
            .header = header,
            .wave_data = null,
            .allocator = allocator,
        };
    }

    pub fn decode(this: This, fname: []const u8) !void {
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
    }

    pub fn deinit(this: This) void {
        this.allocator.destroy(this.header);
        // this.wave_data.deinit();
    }

    pub fn printHeader(this: This) void {
        inline for (std.meta.fields(@TypeOf(this.header.*))) |field| {
            std.log.warn("{s}: {any}", .{ field.name, @as(field.type, @field(this.header.*, field.name)) });
        }
    }
};

test "Wave file header read" {
    const wave = try WaveFile.init(testing.allocator);
    defer wave.deinit();

    try wave.decode("test_music/slowerpace_LOVERS.wav");
    wave.printHeader();
}
