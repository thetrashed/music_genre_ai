const std = @import("std");

const FTypes = enum {
    PNG,
    JPG,
    SVG,
};

fn PlotData(comptime T: type) type {
    return struct {
        const This = @This();

        xs: []T,
        ys: []T,
        label: []const u8,

        pub fn init(xs: []T, ys: []T, label: []const u8) This {
            return .{
                .xs = xs,
                .ys = ys,
                .label = label,
            };
        }
    };
}

pub fn Plot(comptime T: type) type {
    const plotData = PlotData(T);
    return struct {
        const This = @This();

        data: ?std.ArrayList(plotData),

        xlabel: ?[]const u8,
        ylabel: ?[]const u8,
        title: ?[]const u8,

        grid: bool,

        allocator: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator) This {
            return .{
                .data = null,

                .xlabel = null,
                .ylabel = null,
                .title = null,

                .grid = false,

                .allocator = alloc,
            };
        }

        pub fn deinit(this: *This) void {
            if (this.data != null) {
                this.data.?.deinit();
            }
        }

        fn getTermInfo(this: *This, fname: []const u8, ftype: FTypes) ![]const u8 {
            switch (ftype) {
                FTypes.PNG => {
                    return std.fmt.allocPrint(this.allocator,
                        \\reset
                        \\set term pngcairo size 1440,900 enhanced color
                        \\set output "{s}"
                        \\
                    , .{fname});
                },
                FTypes.JPG => {
                    return std.fmt.allocPrint(this.allocator,
                        \\reset
                        \\set term jpeg enhanced
                        \\set output "{s}"
                        \\
                    , .{fname});
                },

                FTypes.SVG => {
                    return std.fmt.allocPrint(this.allocator,
                        \\reset
                        \\set term svg
                        \\set output "{s}"
                        \\
                    , .{fname});
                },
            }
        }

        pub fn addPlot(
            this: *This,
            x: []T,
            y: []T,
            plabel: ?[]const u8,
        ) !void {
            if (this.data == null) {
                this.data = std.ArrayList(plotData).init(this.allocator);
            }
            const data = plotData.init(x, y, plabel orelse "");

            try this.data.?.append(data);
        }

        pub fn showGrid(this: *This) void {
            this.grid = true;
        }

        pub fn setXLabel(this: *This, label: []const u8) void {
            this.xlabel = label;
        }

        pub fn setYLabel(this: *This, label: []const u8) void {
            this.ylabel = label;
        }
        pub fn setTitle(this: *This, title: []const u8) void {
            this.title = title;
        }

        pub fn saveScript(this: *This, sfname: []const u8, ofname: []const u8, oftype: FTypes) !void {
            const script_data = try this.genScript(ofname, oftype);
            defer this.delScript(&script_data);

            const script_file = try std.fs.path.resolve(this.allocator, &[_][]const u8{sfname});
            defer this.allocator.free(script_file);

            const cur_dir = std.fs.cwd();

            var sf_pointer = try cur_dir.createFile(script_file, .{});
            defer sf_pointer.close();

            const writer = sf_pointer.writer();
            for (script_data.items) |item| {
                try writer.writeAll(item);
            }
        }

        pub fn saveFig(this: *This, fname: []const u8, ftype: FTypes) !void {
            var process = std.process.Child.init(
                &[_][]const u8{ "gnuplot", "-p" },
                this.allocator,
            );
            process.stdin_behavior = .Pipe;
            process.spawn() catch |err| {
                std.log.err("Failed to open gnuplot: {any}", .{err});
                return err;
            };
            const writer = process.stdin.?.writer();

            const script_data = try this.genScript(fname, ftype);
            defer this.delScript(&script_data);

            for (script_data.items) |item| {
                try writer.print("{s}", .{item});
            }

            process.stdin.?.close();
        }

        fn delScript(this: *This, script: *const std.ArrayList([]const u8)) void {
            for (script.items) |item| {
                this.allocator.free(item);
            }
            script.deinit();
        }

        fn genScript(this: *This, fname: []const u8, ftype: FTypes) !std.ArrayList([]const u8) {
            var script_data = std.ArrayList([]const u8).init(this.allocator);

            try script_data.append(try this.getTermInfo(fname, ftype));

            if (this.grid) {
                try script_data.append(try std.fmt.allocPrint(
                    this.allocator,
                    "set grid\n",
                    .{},
                ));
            }
            if (this.title != null) {
                try script_data.append(try std.fmt.allocPrint(
                    this.allocator,
                    "set title \"{s}\"\n",
                    .{this.title.?},
                ));
            }
            if (this.xlabel != null) {
                try script_data.append(try std.fmt.allocPrint(
                    this.allocator,
                    "set xlabel \"{s}\"\n",
                    .{this.xlabel.?},
                ));
            }
            if (this.ylabel != null) {
                try script_data.append(try std.fmt.allocPrint(
                    this.allocator,
                    "set ylabel \"{s}\"\n",
                    .{this.ylabel.?},
                ));
            }

            for (0..this.data.?.items.len) |i| {
                try script_data.append(try std.fmt.allocPrint(
                    this.allocator,
                    "{s} '-' u 1:2 with lines lw 2 t \"{s}\"",
                    .{ if (i == 0) "plot" else ", ", this.data.?.items[i].label },
                ));
            }
            try script_data.append(try std.fmt.allocPrint(this.allocator, "\n", .{}));
            for (this.data.?.items) |pdata| {
                for (pdata.xs, pdata.ys) |x, y| {
                    try script_data.append(
                        try std.fmt.allocPrint(this.allocator, "{d} {d}\n", .{ x, y }),
                    );
                }
                try script_data.append(
                    try std.fmt.allocPrint(this.allocator, "e\n", .{}),
                );
            }
            return script_data;
        }
    };
}
