///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const std = @import("std");
const opengl = @import("zopengl");
const gl = opengl.bindings;
const tracy = @import("ztracy");
const math = @import("zmath");

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Vector3 = struct {
    x: f32,
    y: f32,
    z: f32,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Color3 = struct {
    r: f32,
    g: f32,
    b: f32,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Projection = enum {
    perspective,
    orthogonal,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Camera = struct {
    position: math.Vec = .{ 0.5, 2, -4, 1 },
    target: math.Vec = .{ 0, 0, 0, 1 },
    up: math.Vec = .{ 0, 0, 1, 0 }, // z is up - just accept it :-)
    fovy: f32 = 90,
    projection: Projection = .perspective,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Vertex = struct {
    position: Vector3,
    color: Color3,
    normal: Vector3,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const TerrainVertex = struct {
    position: Vector3,
    color: Color3,
    normal: Vector3,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Primative = enum {
    lines,
    line_strip,
    triangles,
    triangle_strip,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub fn Mesh(comptime T: type) type {
    return struct {
        vertexes: std.ArrayList(T),
        indexes: std.ArrayList(u32),

        vao: gl.Uint, // vertex attribute object (the attributes of the vertexes)
        vbo: gl.Uint, // vertex buffer object (the vertex data itself)
        ebo: gl.Uint, // element buffer object (indexes into vertexes)

        vbo_empty: bool = true,
        ebo_empty: bool = true,
        vbo_dirty: bool = true,
        ebo_dirty: bool = true,

        vbo_capacity: usize = 0,
        ebo_capacity: usize = 0,

        vbo_memory: ?[*]T = null,
        ebo_memory: ?[*]u32 = null,

        primative: gl.Uint,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, comptime primative: Primative) !Self {
            var vao: gl.Uint = undefined;
            var vbo: gl.Uint = undefined;
            var ebo: gl.Uint = undefined;

            gl.genVertexArrays(1, &vao);
            gl.genBuffers(1, &vbo);
            gl.genBuffers(1, &ebo);

            gl.bindVertexArray(vao);

            gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
            gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);

            gl.enableVertexAttribArray(0);
            gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "position")));

            gl.enableVertexAttribArray(1);
            gl.vertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "color")));

            gl.enableVertexAttribArray(2);
            gl.vertexAttribPointer(2, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "normal")));

            gl.bindVertexArray(0);

            const gl_primative = switch (primative) {
                .lines => gl.LINES,
                .line_strip => gl.LINE_STRIP,
                .triangles => gl.TRIANGLES,
                .triangle_strip => gl.TRIANGLE_STRIP,
            };

            return .{
                .vertexes = std.ArrayList(T).init(allocator),
                .indexes = std.ArrayList(u32).init(allocator),
                .vao = vao,
                .vbo = vbo,
                .ebo = ebo,
                .primative = gl_primative,
            };
        }

        pub fn deinit(self: *Self) void {
            self.vertexes.deinit();
            self.indexes.deinit();
        }

        pub fn set_capacity(self: *Self, vertex_capacity: usize, index_capacity: usize) !void {
            const dirty_zone = tracy.ZoneNC(@src(), "Mesh.setCapacity", 0x00_80_80_80);
            defer dirty_zone.End();

            try self.vertexes.ensureTotalCapacity(vertex_capacity);
            try self.indexes.ensureTotalCapacity(index_capacity);

            gl.bindVertexArray(self.vao);
            gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);

            gl.bufferData(
                gl.ARRAY_BUFFER,
                @intCast(self.vertexes.capacity * @sizeOf(T)),
                self.vertexes.items.ptr,
                gl.STREAM_DRAW,
            );

            gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.ebo);

            gl.bufferData(
                gl.ELEMENT_ARRAY_BUFFER,
                @intCast(self.indexes.capacity * @sizeOf(u32)),
                self.indexes.items.ptr,
                gl.STREAM_DRAW,
            );

            gl.bindVertexArray(0);

            self.vbo_capacity = self.vertexes.capacity;
            self.ebo_capacity = self.indexes.capacity;
            self.vbo_empty = false;
            self.ebo_empty = false;
        }

        const SavePoint = struct {
            vi: usize,
            ii: usize,
        };

        pub fn savepoint(self: *Self) SavePoint {
            return .{ .vi = self.vertexes.items.len, .ii = self.indexes.items.len };
        }

        pub fn restore(self: *Self, sp: SavePoint) void {
            self.vertexes.items.len = sp.vi;
            self.indexes.items.len = sp.ii;
        }

        pub fn addVertex(self: *Self, vertex: T) !u32 {
            const index = self.vertexes.items.len;
            try self.vertexes.append(vertex);
            self.vbo_dirty = true;
            return @intCast(index);
        }

        pub fn addIndex(self: *Self, index: u32) !void {
            try self.indexes.append(index);
            self.ebo_dirty = true;
        }

        pub fn reset(self: *Self) !void {
            self.vertexes.clearRetainingCapacity();
            self.indexes.clearRetainingCapacity();
        }

        pub fn unmap_memory(self: *Self) void {
            gl.bindVertexArray(self.vao);
            if (self.vbo_memory != null) {
                gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
                _ = gl.unmapBuffer(gl.ARRAY_BUFFER);
                self.vbo_memory = null;
            }
            if (self.ebo_memory != null) {
                gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.ebo);
                _ = gl.unmapBuffer(gl.ELEMENT_ARRAY_BUFFER);
                self.ebo_memory = null;
            }
            gl.bindVertexArray(0);
        }

        pub fn get_vbo_memory(self: *Self) [*]T {
            if (self.vbo_memory) |mem| {
                return mem;
            }

            gl.bindVertexArray(self.vao);
            gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
            defer gl.bindVertexArray(0);
            self.vbo_memory = @alignCast(@ptrCast(gl.mapBuffer(gl.ARRAY_BUFFER, gl.WRITE_ONLY)));
            return self.vbo_memory.?;
        }

        pub fn get_ebo_memory(self: *Self) [*]u32 {
            if (self.ebo_memory) |mem| {
                return mem;
            }

            gl.bindVertexArray(self.vao);
            gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.ebo);
            defer gl.bindVertexArray(0);
            self.ebo_memory = @alignCast(@ptrCast(gl.mapBuffer(gl.ELEMENT_ARRAY_BUFFER, gl.WRITE_ONLY)));
            return self.ebo_memory.?;
        }

        pub fn copy_data(self: *Self) void {
            if (self.vbo_empty) {
                const dirty_zone = tracy.ZoneNC(@src(), "vbo_empty", 0x00_80_80_80);
                defer dirty_zone.End();

                // std.debug.print ("VBO Empty {} {}\n", .{self.vbo, self.vertexes.items.len});

                gl.bindVertexArray(self.vao);
                gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
                gl.bufferData(
                    gl.ARRAY_BUFFER,
                    @intCast(self.vertexes.items.len * @sizeOf(T)),
                    self.vertexes.items.ptr,
                    gl.STREAM_DRAW,
                );
                self.vbo_empty = false;
                self.vbo_dirty = false;
            }

            if (self.vbo_dirty) {
                const dirty_zone = tracy.ZoneNC(@src(), "ebo_dirty", 0x00_80_80_80);
                defer dirty_zone.End();

                // std.debug.print ("VBO Dirty {} {}\n", .{self.vbo, self.vertexes.items.len});

                gl.bindVertexArray(self.vao);
                gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
                gl.bufferSubData(
                    gl.ARRAY_BUFFER,
                    0,
                    @intCast(self.vertexes.items.len * @sizeOf(T)),
                    self.vertexes.items.ptr,
                );
                self.vbo_dirty = false;
            }

            if (self.ebo_empty) {
                const dirty_zone = tracy.ZoneNC(@src(), "ebo_empty", 0x00_80_80_80);
                defer dirty_zone.End();

                // std.debug.print ("EBO Empty {} {}\n", .{self.ebo, self.indexes.items.len});

                gl.bindVertexArray(self.vao);
                gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.ebo);
                gl.bufferData(
                    gl.ELEMENT_ARRAY_BUFFER,
                    @intCast(self.indexes.items.len * @sizeOf(u32)),
                    self.indexes.items.ptr,
                    gl.STREAM_DRAW,
                );
                self.ebo_empty = false;
                self.ebo_dirty = false;
            }

            if (self.ebo_dirty) {
                const dirty_zone = tracy.ZoneNC(@src(), "ebo_dirty", 0x00_80_80_80);
                defer dirty_zone.End();

                // std.debug.print ("EBO Dirty {} {}\n", .{self.ebo, self.indexes.items.len});

                gl.bindVertexArray(self.vao);
                gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.ebo);
                gl.bufferSubData(
                    gl.ELEMENT_ARRAY_BUFFER,
                    0,
                    @intCast(self.indexes.items.len * @sizeOf(u32)),
                    self.indexes.items.ptr,
                );
                self.ebo_dirty = false;
            }

            gl.bindVertexArray(0);
        }

        pub fn render(self: *Self) void {
            const zone = tracy.ZoneNC(@src(), "mesh.render", 0x00_80_80_80);
            defer zone.End();

            self.copy_data();

            gl.bindVertexArray(self.vao);

            // std.debug.print ("Draw {} {}\n", .{self.vbo, self.indexes.items.len});
            gl.drawElements(self.primative, @intCast(self.indexes.items.len), gl.UNSIGNED_INT, @ptrFromInt(0));

            gl.bindVertexArray(0);
        }
    };
}

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Shader = struct {
    id: gl.Uint,
    label: []const u8,

    pub fn init(allocator: std.mem.Allocator, label: []const u8, source: []const u8) !Shader {
        const zone = tracy.ZoneNC(@src(), "shader.init", 0x00_80_80_80);
        defer zone.End();

        var vertex_source = std.ArrayList(u8).init(allocator);
        defer vertex_source.deinit();
        var fragment_source = std.ArrayList(u8).init(allocator);
        defer fragment_source.deinit();

        var state: enum { unknown, vertex, fragment } = .unknown;

        var iter = std.mem.splitAny(u8, source, "\n");
        while (iter.next()) |line| {
            if (std.mem.eql(u8, line, "@vertex")) {
                state = .vertex;
            } else if (std.mem.eql(u8, line, "@fragment")) {
                state = .fragment;
            } else if (state == .vertex) {
                try vertex_source.appendSlice(line);
                try vertex_source.append('\n');
            } else if (state == .fragment) {
                try fragment_source.appendSlice(line);
                try fragment_source.append('\n');
            }
        }

        try vertex_source.append('\x00');
        try fragment_source.append('\x00');

        const vertex_shader = gl.createShader(gl.VERTEX_SHADER);
        const fragment_shader = gl.createShader(gl.FRAGMENT_SHADER);

        gl.shaderSource(vertex_shader, 1, &vertex_source.items.ptr, null);
        gl.compileShader(vertex_shader);

        var success: c_int = undefined;
        gl.getShaderiv(vertex_shader, gl.COMPILE_STATUS, &success);
        if (success == 0) {
            var buffer: [512]u8 = undefined;
            var len: c_int = undefined;
            gl.getShaderInfoLog(vertex_shader, buffer.len, &len, &buffer);
            std.debug.print("ERROR: {s}\n", .{buffer[0..@intCast(len)]});
            std.debug.print("----\n{s}\n----\n", .{vertex_source.items});
            return error.VertexCompilationFailed;
        }

        gl.shaderSource(fragment_shader, 1, &fragment_source.items.ptr, null);
        gl.compileShader(fragment_shader);

        gl.getShaderiv(fragment_shader, gl.COMPILE_STATUS, &success);
        if (success == 0) {
            var buffer: [512]u8 = undefined;
            var len: c_int = undefined;
            gl.getShaderInfoLog(fragment_shader, buffer.len, &len, &buffer);
            std.debug.print("ERROR: {}/{} {s}\n", .{ buffer.len, len, buffer[0..@intCast(len)] });
            std.debug.print("----\n{s}\n----\n", .{fragment_source.items});
            return error.FragmentCompilationFailed;
        }

        const id = gl.createProgram();
        gl.attachShader(id, vertex_shader);
        gl.attachShader(id, fragment_shader);
        gl.linkProgram(id);

        gl.getProgramiv(id, gl.LINK_STATUS, &success);
        if (success == 0) {
            var buffer: [512]u8 = undefined;
            var len: c_int = undefined;
            gl.getProgramInfoLog(fragment_shader, buffer.len, &len, &buffer);
            std.debug.print("ERROR: {}/{} {s}\n", .{ buffer.len, len, buffer[0..@intCast(len)] });
            return error.ShaderLinkFailed;
        }
        gl.deleteShader(vertex_shader);
        gl.deleteShader(fragment_shader);
        return .{ .label = label, .id = id };
    }

    pub fn use(self: Shader) void {
        const zone = tracy.ZoneNC(@src(), "shader.use", 0x00_80_80_80);
        defer zone.End();
        gl.useProgram(self.id);
    }

    pub fn end(self: Shader) void {
        _ = self;
        const zone = tracy.ZoneNC(@src(), "shader.end", 0x00_80_80_80);
        defer zone.End();
        gl.useProgram(0);
    }

    pub fn setUniform3f(self: Shader, name: [*c]const u8, value: [3]f32) void {
        const zone = tracy.ZoneNC(@src(), "shader.setUniform3f", 0x00_80_80_80);
        defer zone.End();
        const location = gl.getUniformLocation(self.id, name);
        if (location == -1) {
            // std.debug.print("Unknown uniform {s} in {s}\n", .{ name, self.label });
        }
        else
        {
            gl.uniform3f(location, value[0], value[1], value[2]);
        }
    }

    pub fn setUniform4f(self: Shader, name: [*c]const u8, value: [4]f32) void {
        const zone = tracy.ZoneNC(@src(), "shader.setUniform4f", 0x00_80_80_80);
        defer zone.End();
        const location = gl.getUniformLocation(self.id, name);
        if (location == -1) {
            // std.debug.print("Unknown uniform {s} is {s}\n", .{ name, self.label });
        }
        else
        {
            gl.uniform4f(location, value[0], value[1], value[2], value[3]);
        }
    }

    pub fn setUniformMat(self: Shader, name: [*c]const u8, value: math.Mat) void {
        const zone = tracy.ZoneNC(@src(), "shader.setUniformMat", 0x00_80_80_80);
        defer zone.End();
        const location = gl.getUniformLocation(self.id, name);
        if (location == -1) {
            // std.debug.print("Unknown uniform {s} is {s}\n", .{ name, self.label });
        }
        else
        {
            gl.uniformMatrix4fv(location, 1, gl.FALSE, math.arrNPtr(&value));
        }
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
