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
    pos: Vector3,
    col: Color3,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Primative = enum {
    lines,
    triangles,
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Mesh = struct {
    vertexes: std.ArrayList(Vertex),
    indexes: std.ArrayList(u32),

    vao: gl.Uint, // vertex attribute object (the attributes of the vertexes)
    vbo: gl.Uint, // vertex buffer object (the vertex data itself)
    ebo: gl.Uint, // element buffer object (indexes into vertexes)

    vbo_dirty: bool = true,
    ebo_dirty: bool = true,

    primative: gl.Uint,

    pub fn init(allocator: std.mem.Allocator, comptime primative: Primative) !Mesh {
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
        gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "pos")));

        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), @ptrFromInt(@offsetOf(Vertex, "col")));

        gl.bindVertexArray(0);

        const gl_primative = switch (primative) {
            .lines => gl.LINES,
            .triangles => gl.TRIANGLES,
        };

        return .{
            .vertexes = std.ArrayList(Vertex).init(allocator),
            .indexes = std.ArrayList(u32).init(allocator),
            .vao = vao,
            .vbo = vbo,
            .ebo = ebo,
            .primative = gl_primative,
        };
    }

    pub fn deinit(self: *Mesh) void {
        self.vertexes.deinit();
        self.indexes.deinit();
    }

    pub fn addVertex(self: *Mesh, vertex: Vertex) !u32 {
        const index = self.vertexes.items.len;
        try self.vertexes.append(vertex);
        self.vbo_dirty = true;
        return @intCast(index);
    }

    pub fn addIndex(self: *Mesh, index: u32) !void {
        try self.indexes.append(index);
        self.ebo_dirty = true;
    }

    pub fn render(self: *Mesh) void {
        const zone = tracy.ZoneNC(@src(), "mesh.render", 0x00_80_80_80);
        defer zone.End();

        gl.bindVertexArray(self.vao);

        if (self.vbo_dirty) {
            const dirty_zone = tracy.ZoneNC(@src(), "vbo_dirty", 0x00_80_80_80);
            defer dirty_zone.End();

            gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
            gl.bufferData(
                gl.ARRAY_BUFFER,
                @intCast(self.vertexes.items.len * @sizeOf(@TypeOf(self.vertexes.items[0]))),
                &self.vertexes.items[0],
                gl.STATIC_DRAW,
            );
            self.vbo_dirty = false;
        }

        if (self.ebo_dirty) {
            const dirty_zone = tracy.ZoneNC(@src(), "ebo_dirty", 0x00_80_80_80);
            defer dirty_zone.End();

            gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.ebo);
            gl.bufferData(
                gl.ELEMENT_ARRAY_BUFFER,
                @intCast(self.indexes.items.len * @sizeOf(@TypeOf(self.indexes.items[0]))),
                &self.indexes.items[0],
                gl.STATIC_DRAW,
            );
            self.ebo_dirty = false;
        }

        gl.drawElements(self.primative, @intCast(self.indexes.items.len), gl.UNSIGNED_INT, @ptrFromInt(0));

        gl.bindVertexArray(0);
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Shader = struct {
    id: gl.Uint,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) !Shader {
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
        return .{ .id = id };
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
            std.debug.print("Unknown uniform {s}\n", .{name});
        }
        gl.uniform3f(location, value[0], value[1], value[2]);
    }

    pub fn setUniform4f(self: Shader, name: [*c]const u8, value: [4]f32) void {
        const zone = tracy.ZoneNC(@src(), "shader.setUniform4f", 0x00_80_80_80);
        defer zone.End();
        const location = gl.getUniformLocation(self.id, name);
        if (location == -1) {
            std.debug.print("Unknown uniform {s}\n", .{name});
        }
        gl.uniform4f(location, value[0], value[1], value[2], value[3]);
    }

    pub fn setUniformMat(self: Shader, name: [*c]const u8, value: math.Mat) void {
        const zone = tracy.ZoneNC(@src(), "shader.setUniformMat", 0x00_80_80_80);
        defer zone.End();
        const location = gl.getUniformLocation(self.id, name);
        if (location == -1) {
            std.debug.print("Unknown uniform {s}\n", .{name});
        }
        gl.uniformMatrix4fv(location, 1, gl.FALSE, math.arrNPtr(&value));
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
