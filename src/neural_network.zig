const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.neural_network);

const Neuron = struct {
    const Self = @This();

    actv: f32,
    out_weights: []f32,
    bias: f32,
    z: f32,
    dactv: f32,
    dw: []f32,
    dbias: f32,
    dz: f32,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, num_out_weights: usize) !Self {
        return .{
            .actv = 0.0,
            .out_weights = try allocator.alloc(f32, num_out_weights),
            .bias = 0.0,
            .z = 0.0,
            .dactv = 0.0,
            .dw = try allocator.alloc(f32, num_out_weights),
            .dbias = 0.0,
            .dz = 0.0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.out_weigths);
        self.allocator.free(self.dw);
    }
};

const Layer = struct {
    const Self = @This();

    num_neu: usize,
    neu: []Neuron,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, num_neurons: usize) !Self {
        return .{
            .num_neu = 0,
            .neu = try allocator.alloc(Neuron, num_neurons),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.neu);
    }
};

pub fn createArchitecture(allocator: mem.Allocator, num_layers: usize, num_neurons: []usize) ![]Layer {
    var layers = try allocator.alloc(Layer, num_layers);

    for (0..layers.len) |i| {
        layers[i] = try Layer.init(allocator, num_neurons[i]);
        log.info("Created layer: {d}", .{i + 1});
        log.info("Number of Neurons in Layer {d}: {d}", .{ i + 1, layers[i].num_neu });

        for (0..num_neurons[i]) |j| {
            if (i < (num_layers - 1)) {
                layers[i].neu[j] = try Neuron.init(allocator, num_nurons[i + 1]);
            }
            log.info("Neuron {d} in Layer {d} created", .{ j + 1, i + 1 });
        }
    }
    
    // TODO: Initialise weights
}
