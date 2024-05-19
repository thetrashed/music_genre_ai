const std = @import("std");
const mem = std.mem;
const math = std.math;
const testing = std.testing;
const log = std.log.scoped(.neural_network);

const seed: u64 = 1000;
var prng = std.rand.DefaultPrng.init(seed);

const Neuron = struct {
    const Self = @This();

    actv: f32,
    out_weights: ?[]f32,
    bias: f32,
    z: f32,
    dactv: f32,
    dw: ?[]f32,
    dbias: f32,
    dz: f32,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, num_out_weights: usize) !Self {
        var ret_struct = Self{
            .actv = 0.0,
            .out_weights = null,
            .bias = 0.0,
            .z = 0.0,
            .dactv = 0.0,
            .dw = null,
            .dbias = 0.0,
            .dz = 0.0,
            .allocator = allocator,
        };
        if (num_out_weights > 0) {
            ret_struct.out_weights = try ret_struct.allocator.alloc(f32, num_out_weights);
            ret_struct.dw = try ret_struct.allocator.alloc(f32, num_out_weights);
        }
        return ret_struct;
    }

    pub fn writeToFile(self: Self, writer: anytype) !void {
        var slice = mem.sliceAsBytes(self.out_weights.?);
        try writer.writeAll(slice);

        slice = mem.sliceAsBytes(self.dw.?);
        try writer.writeAll(slice);

        try writer.print("{d}", .{self.bias});
    }

    pub fn deinit(self: Self) void {
        if (self.out_weights) |out_weights| {
            self.allocator.free(out_weights);
        }
        if (self.dw) |dw| {
            self.allocator.free(dw);
        }
    }
};

const Layer = struct {
    const Self = @This();

    neu: []Neuron,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, num_neurons: usize) !Self {
        return .{
            .neu = try allocator.alloc(Neuron, num_neurons),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        if (self.neu.len > 0) {
            for (self.neu) |*neuron| {
                neuron.deinit();
            }
        }
        self.allocator.free(self.neu);
    }
};

pub fn createArchitecture(allocator: mem.Allocator, num_layers: usize, num_neurons: []usize) ![]Layer {
    var layers = try allocator.alloc(Layer, num_layers);

    for (0..layers.len) |i| {
        layers[i] = try Layer.init(allocator, num_neurons[i]);
        log.info("Created layer: {d}", .{i + 1});
        log.info("Number of Neurons in Layer {d}: {d}", .{ i + 1, layers[i].neu.len });

        for (0..num_neurons[i]) |j| {
            if (i < (num_layers - 1)) {
                layers[i].neu[j] = try Neuron.init(allocator, num_neurons[i + 1]);
            } else {
                layers[i].neu[j] = try Neuron.init(allocator, 0);
            }
            log.info("Neuron {d} in Layer {d} created", .{ j + 1, i + 1 });
        }
    }

    for (0..layers.len - 1) |i| {
        for (0..layers[i].neu.len) |j| {
            for (0..layers[i + 1].neu.len) |k| {
                layers[i].neu[j].out_weights.?[k] = prng.random().float(f32);
                // log.info("{d}:w[{d}][{d}]: {d}", .{ k, i, j, layers[i].neu[j].out_weights.?[k] });
                layers[i].neu[j].dw.?[k] = 0.0;
            }
            if (i > 0) {
                layers[i].neu[j].bias = prng.random().float(f32);
            }
        }
    }

    for (0..num_neurons[num_layers - 1]) |num_neuron| {
        layers[num_layers - 1].neu[num_neuron].bias = prng.random().float(f32);
    }

    return layers;
}

pub fn destroyArchitecture(allocator: mem.Allocator, architecture: []Layer) void {
    for (architecture) |layer| {
        layer.deinit();
    }
    allocator.free(architecture);
}

pub fn forwardPropagation(architecture: []Layer) void {
    for (1..architecture.len) |i| {
        for (architecture[i].neu, 0..) |*neuron, j| {
            neuron.z = neuron.bias;
            for (0..architecture[i - 1].neu.len) |k| {
                neuron.z += architecture[i - 1].neu[k].out_weights.?[j] * architecture[i - 1].neu[k].actv;
            }

            // Relu Activation for Hidden Layers
            if (i < architecture.len - 1) {
                if (neuron.z < 0) {
                    neuron.actv = 0;
                } else {
                    neuron.actv = neuron.z;
                }
            } else {
                // Sigmoid for output layer
                neuron.actv = 1 / (1 + math.exp(-neuron.z));
                // log.info("Output: {d}", .{neuron.actv});
            }
        }
    }
}

pub fn backwardPropagation(architecture: []Layer, desired_outputs: [][]f32, p: usize) void {
    for (architecture[architecture.len - 1].neu, 0..) |*neuron, j| {
        neuron.dz = (neuron.actv - desired_outputs[p][j]) * (neuron.actv) * (1 - neuron.actv);
        for (architecture[architecture.len - 2].neu) |*prev_neuron| {
            prev_neuron.dw.?[j] = (neuron.dz * prev_neuron.actv);
            prev_neuron.dactv = prev_neuron.out_weights.?[j] * neuron.dz;
        }
        neuron.dbias = neuron.dz;
    }

    var i: usize = architecture.len - 2;
    while (i > 0) : (i -= 1) {
        for (architecture[i].neu, 0..) |*neuron, j| {
            if (neuron.z >= 0) {
                neuron.dz = neuron.dactv;
            } else {
                neuron.dz = 0;
            }

            for (0..architecture[i - 1].neu.len - 1) |k| {
                architecture[i - 1].neu[k].dw.?[j] = neuron.dz * architecture[i - 1].neu[k].actv;
                if (i > 1) {
                    architecture[i - 1].neu[k].dactv = architecture[i - 1].neu[k].out_weights.?[j] * neuron.dz;
                }
            }

            neuron.dbias = neuron.dz;
        }
    }
}

pub fn updateWeights(architecture: []Layer, alpha: f32) void {
    for (0..architecture.len - 1) |i| {
        for (architecture[i].neu) |*neuron| {
            for (0..architecture[i + 1].neu.len) |k| {
                neuron.out_weights.?[k] -= alpha * neuron.dw.?[k];
            }
            neuron.bias -= alpha * neuron.dbias;
        }
    }
}

pub fn feedInput(layer: *Layer, input: [][]f32, input_index: usize) void {
    for (layer.neu, 0..) |*neuron, j| {
        neuron.actv = input[input_index][j];
        // log.info("Input: {d}", .{neuron.actv});
    }
}

test "xor_nn" {
    const allocator = testing.allocator;

    var arch_type = [_]usize{ 2, 4, 4, 1 };
    const architecture = try createArchitecture(allocator, 4, &arch_type);
    defer destroyArchitecture(allocator, architecture);

    const alpha = 0.15;

    var outputs = try allocator.alloc([]f32, 4);
    for (0..outputs.len) |i| {
        outputs[i] = try allocator.alloc(f32, 1);
    }
    defer {
        for (outputs) |o| {
            allocator.free(o);
        }
        allocator.free(outputs);
    }

    var inputs: [][]f32 = try allocator.alloc([]f32, 4);
    for (0..inputs.len) |i| {
        inputs[i] = try allocator.alloc(f32, 2);
    }
    defer {
        for (inputs) |i| {
            allocator.free(i);
        }
        allocator.free(inputs);
    }

    inputs[0][0] = 0.0;
    inputs[0][1] = 0.0;
    inputs[1][0] = 0.0;
    inputs[1][1] = 1.0;
    inputs[2][0] = 1.0;
    inputs[2][1] = 0.0;
    inputs[3][0] = 1.0;
    inputs[3][1] = 1.0;

    outputs[0][0] = 0.0;
    outputs[1][0] = 1.0;
    outputs[2][0] = 1.0;
    outputs[3][0] = 0.0;

    var it: usize = 0;
    while (it < 20000) : (it += 1) {
        for (0..inputs.len) |i| {
            feedInput(&architecture[0], inputs, i);
            forwardPropagation(architecture);
            backwardPropagation(architecture, outputs, i);
            updateWeights(architecture, alpha);
        }
    }

    const test_file = "test_file.model";
    var tf_ptr = std.fs.cwd().openFile(test_file, .{}) catch |err| switch (err) {
        error.FileNotFound => try std.fs.cwd().createFile(test_file, .{}),
        else => return err,
    };
    defer tf_ptr.close();

    const writer = tf_ptr.writer();
    for (architecture, 0..) |layer, i| {
        for (layer.neu) |neuron| {
            std.log.warn("layer no: {d}", .{i});
            try neuron.writeToFile(writer);
        }
    }

    // Input testing
    log.warn("Input: {d} {d}", .{ 0.0, 0.0 });
    architecture[0].neu[0].actv = 0.0;
    architecture[0].neu[1].actv = 0.0;
    forwardPropagation(architecture);
    try testing.expectEqual(0.0, math.round(architecture[architecture.len - 1].neu[0].actv));

    log.warn("Input: {d} {d}", .{ 1.0, 0.0 });
    architecture[0].neu[0].actv = 1.0;
    architecture[0].neu[1].actv = 0.0;
    forwardPropagation(architecture);
    try testing.expectEqual(1.0, math.round(architecture[architecture.len - 1].neu[0].actv));

    log.warn("Input: {d} {d}", .{ 0.0, 1.0 });
    architecture[0].neu[0].actv = 0.0;
    architecture[0].neu[1].actv = 1.0;
    forwardPropagation(architecture);
    try testing.expectEqual(1.0, math.round(architecture[architecture.len - 1].neu[0].actv));

    log.warn("Input: {d} {d}", .{ 1.0, 1.0 });
    architecture[0].neu[0].actv = 1.0;
    architecture[0].neu[1].actv = 1.0;
    forwardPropagation(architecture);
    try testing.expectEqual(0.0, math.round(architecture[architecture.len - 1].neu[0].actv));
}
