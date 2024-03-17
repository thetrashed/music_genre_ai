const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const os = std.os;

const Allocator = mem.Allocator;

const WaveHeader = struct {
    const Self = @This();

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

    pub fn reset(this: *Self) void {
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

pub const WaveFile = struct {
    const Self = @This();

    header: ?*WaveHeader,
    mapped_data: ?[]align(mem.page_size) u8,
    chan1_position: usize,
    chan2_position: usize,
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return .{
            .header = null,
            .mapped_data = null,
            .chan1_position = 0,
            .chan2_position = 0,
            .allocator = allocator,
        };
    }

    pub fn decodeFile(self: *Self, fname: []const u8) !void {
        const fname_abs = try std.fs.realpathAlloc(self.allocator, fname);
        defer self.allocator.free(fname_abs);

        const file = try std.fs.openFileAbsolute(fname_abs, .{});
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        const reader = buf_reader.reader();

        self.header = try self.allocator.create(WaveHeader);
        self.header.?.magic = try reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &self.header.?.magic, "RIFF")) {
            return error.InvalidRiffID;
        }
        self.header.?.chunk_size = try reader.readInt(u32, .little);

        self.header.?.format = try reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &self.header.?.format, "WAVE")) {
            return error.InvalidWaveID;
        }

        self.header.?.fmt_magic = try reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &self.header.?.fmt_magic, "fmt ")) {
            return error.InvalidFmtID;
        }
        self.header.?.fmt_size = try reader.readInt(u32, .little);
        self.header.?.audio_format = try reader.readInt(u16, .little);
        self.header.?.channels = try reader.readInt(u16, .little);
        self.header.?.sample_rate = try reader.readInt(u32, .little);
        self.header.?.byte_rate = try reader.readInt(u32, .little);
        self.header.?.block_align = try reader.readInt(u16, .little);
        self.header.?.bits_per_sample = try reader.readInt(u16, .little);

        if (self.header.?.channels == 2) {
            self.chan2_position = switch (self.header.?.bits_per_sample) {
                8 => 1,
                16 => 2,
                else => return error.NotSupportedOrImplemented,
            };
        }

        // Skip all subchunks till the "data" subchunk
        // while (true) {
        //     const tmp = try reader.readBytesNoEof(4);
        //     if (std.mem.eql(u8, &tmp, "data")) {
        //         break;
        //     }
        //     const skip_size = try reader.readInt(u32, .little);
        //     try reader.skipBytes(skip_size, .{});
        // }
        self.header.?.data_magic = try reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &self.header.?.data_magic, "data")) {
            return error.InvalidDataID;
        }
        // self.header.?.data_magic = [_]u8{ 'd', 'a', 't', 'a' };
        self.header.?.data_size = try reader.readInt(u32, .little);

        self.mapped_data = try os.mmap(null, self.header.?.data_size, os.PROT.READ, os.MAP.PRIVATE, file.handle, 0);

        self.printHeader();
    }

    pub fn getAllDataSliceAlloc(self: *Self, allocator: Allocator, channel: ?usize) ![]i32 {
        const ch = channel orelse 1;
        const data_size = (8 * self.header.?.data_size / self.header.?.bits_per_sample) / self.header.?.channels;

        return self.getSampleSliceAlloc(allocator, if (ch == 1) 0 else 1, data_size, ch);
    }

    pub fn getSampleSliceAlloc(self: *Self, allocator: Allocator, start_sample: usize, size: usize, channel: ?usize) ![]i32 {
        const ch = channel orelse 1;
        const ssample = (start_sample * ch * self.header.?.bits_per_sample) / 8;
        const ch_data_size = (8 * self.header.?.data_size / self.header.?.bits_per_sample) / self.header.?.channels;

        var osize: usize = undefined;
        if (ssample + size > ch_data_size) {
            osize = (ch_data_size - ssample) * 8 / self.header.?.bits_per_sample;
        } else {
            osize = size * 8 / self.header.?.bits_per_sample;
        }
        var out_data = try allocator.alloc(i32, osize);

        if (ch == 1) {
            self.chan1_position = ssample;
        } else {
            self.chan2_position = ssample;
        }
        var i: usize = 0;
        while (i < out_data.len) : (i += 1) {
            switch (ch) {
                1 => {
                    switch (self.header.?.bits_per_sample) {
                        8 => {
                            out_data[i] = self.mapped_data.?[self.chan1_position];
                            if (self.header.?.channels == 1) {
                                self.chan1_position += 1;
                            } else {
                                self.chan1_position += 2;
                            }
                        },
                        16 => {
                            out_data[i] = mem.bytesToValue(i32, self.mapped_data.?[self.chan1_position .. self.chan1_position + 2]);
                            if (self.header.?.channels == 1) {
                                self.chan1_position += 2;
                            } else {
                                self.chan1_position += 4;
                            }
                        },
                        else => return error.NotSupportedOrImplemented,
                    }
                },
                2 => {
                    switch (self.header.?.bits_per_sample) {
                        8 => {
                            out_data[i] = self.mapped_data.?[self.chan2_position];
                            self.chan2_position += 2;
                        },
                        16 => {
                            out_data[i] = mem.bytesToValue(i32, self.mapped_data.?[self.chan2_position .. self.chan2_position + 2]);
                            self.chan2_position += 4;
                        },
                        else => return error.NotSupportedOrImplemented,
                    }
                },
                else => return error.NotSupportedOrImplemented,
            }
        }

        return out_data;
    }

    pub fn deinit(self: Self) void {
        if (self.header) |header| {
            self.allocator.destroy(header);
        }

        if (self.mapped_data) |mapped_data| {
            os.munmap(mapped_data);
        }
    }

    pub fn printHeader(self: Self) void {
        inline for (std.meta.fields(@TypeOf(self.header.?.*))) |field| {
            std.log.warn("{s}: {any}", .{ field.name, @as(field.type, @field(self.header.?.*, field.name)) });
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
        "test_music/test1",
        "test_music/wavTones.com.unregistred.rect_-10dBFS_12samples",
        "test_music/wavTones.com.unregistred.rect_-6dBFS_5samples",
        // "test_music/Free_Test_Data_10MB_WAV",
        // "test_music/mono16_sinewave",
        // "test_music/stereo16_mixture",
        // "test_music/stereo16_sine_cosine",
        // "test_music/stereo16_sine",
        // "test_music/test1",
        // "test_music/wavTones.com.unregistred.rect_-10dBFS_12samples",
        // "test_music/wavTones.com.unregistred.rect_-6dBFS_5samples",
        // "test_music/project_raven",
    };

    inline for (fnames) |fname| {
        std.log.warn("Processing {s}", .{fname});
        var wave = WaveFile.init(testing.allocator);
        defer wave.deinit();

        wave.decodeFile(fname ++ ".wav") catch |err| {
            std.log.err("{}", .{err});
            std.os.exit(1);
        };

        const x = try wave.getAllDataSliceAlloc(testing.allocator, 2);
        defer testing.allocator.free(x);

        const file = try std.fs.cwd().createFile(fname ++ ".dat", .{});
        defer file.close();
        var buf_writer = std.io.bufferedWriter(file.writer());
        const writer = buf_writer.writer();
        for (0..x.len) |i| {
            try writer.print("{d},{d}\n", .{ i, x[i] });
        }
        try buf_writer.flush();
    }
}
