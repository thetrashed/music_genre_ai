const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.neural_network);

const seed: u64 = @truncate(@as(u128, @bitCast(std.time.nanoTimestamp())));
var prng = std.rand.DefaultPrng.init(seed);

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

    pub fn initWeights(self: Self, layer_no: usize) void {
        for (self.neu) |*neuron| {
            for (neuron.out_weights, neuron.dw) |*out_weight, *dw| {
                out_weight = prng.random().float(f32);
                dw = 0.0;
            }
            if (layer_no > 0) {
                neuron.bias = prng.random().float(f32);
            }
        }
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
                layers[i].neu[j] = try Neuron.init(allocator, num_neurons[i + 1]);
            }
            log.info("Neuron {d} in Layer {d} created", .{ j + 1, i + 1 });
        }
    }

    for (0.., layers) |i, *layer| {
        layer.initWeights(i);
    }
    for (0..num_neurons[num_layers - 1]) |num_neuron| {
        layers[num_layers - 1].neu[num_neuron].bias = prng.random().float(f32);
    }
}
