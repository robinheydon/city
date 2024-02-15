///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

const std = @import("std");
const opengl = @import("zopengl");
const gl = opengl.bindings;

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

pub const Vertex = struct {
    pos: Vector3,
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

    pub fn init(allocator: std.mem.Allocator) !Mesh {
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
        gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vector3), @ptrFromInt (0));

        gl.bindVertexArray(0);

        return .{
            .vertexes = std.ArrayList(Vertex).init(allocator),
            .indexes = std.ArrayList(u32).init(allocator),
            .vao = vao,
            .vbo = vbo,
            .ebo = ebo,
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
        return @intCast (index);
    }

    pub fn addIndex(self: *Mesh, index: u32) !void {
        try self.indexes.append(index);
        self.ebo_dirty = true;
    }

    pub fn render(self: *Mesh) void {
        gl.bindVertexArray(self.vao);

        if (self.vbo_dirty) {
            gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
            gl.bufferData(
                gl.ARRAY_BUFFER,
                @intCast (self.vertexes.items.len * @sizeOf(@TypeOf (self.vertexes.items[0]))),
                &self.vertexes.items[0],
                gl.STATIC_DRAW,
            );
            self.vbo_dirty = false;
        }

        if (self.ebo_dirty) {
            gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.ebo);
            gl.bufferData(
                gl.ELEMENT_ARRAY_BUFFER,
                @intCast (self.indexes.items.len * @sizeOf(@TypeOf (self.indexes.items[0]))),
                &self.indexes.items[0],
                gl.STATIC_DRAW,
            );
            self.ebo_dirty = false;
        }

        gl.drawElements (gl.TRIANGLES, @intCast (self.indexes.items.len), gl.UNSIGNED_INT, @ptrFromInt (0));

        gl.bindVertexArray (0);
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////

pub const Shader = struct {
    id: gl.Uint,

    pub fn init (allocator: std.mem.Allocator, source: []const u8) !Shader
    {
        var vertex_source = std.ArrayList (u8).init (allocator);
        defer vertex_source.deinit ();
        var fragment_source = std.ArrayList (u8).init (allocator);
        defer fragment_source.deinit ();

        var state : enum { unknown, vertex, fragment } = .unknown;

        var iter = std.mem.splitAny (u8, source, "\n");
        while (iter.next ()) |line|
        {
            if (std.mem.eql (u8, line, "@vertex"))
            {
                state = .vertex;
            }
            else if (std.mem.eql (u8, line, "@fragment"))
            {
                state = .fragment;
            }
            else if (state == .vertex)
            {
                try vertex_source.appendSlice (line);
                try vertex_source.append ('\n');
            }
            else if (state == .fragment)
            {
                try fragment_source.appendSlice (line);
                try fragment_source.append ('\n');
            }
        }

        const vertex_shader = gl.createShader (gl.VERTEX_SHADER);
        const fragment_shader = gl.createShader (gl.FRAGMENT_SHADER);

        gl.shaderSource (vertex_shader, 1, &vertex_source.items.ptr, null);
        gl.compileShader (vertex_shader);

        var success : c_int = undefined;
        gl.getShaderiv (vertex_shader, gl.COMPILE_STATUS, &success);
        if (success == 0)
        {
            var buffer : [512]u8 = undefined;
            var len : c_int = undefined;
            gl.getShaderInfoLog (vertex_shader, buffer.len, &len, &buffer);
            std.debug.print ("ERROR: {s}\n", .{buffer[0..@intCast (len)]});
            std.debug.print ("----\n{s}\n----\n", .{vertex_source.items});
            return error.VertexCompilationFailed;
        }

        gl.shaderSource (fragment_shader, 1, &fragment_source.items.ptr, null);
        gl.compileShader (fragment_shader);

        gl.getShaderiv (fragment_shader, gl.COMPILE_STATUS, &success);
        if (success == 0)
        {
            var buffer : [512]u8 = undefined;
            var len : c_int = undefined;
            gl.getShaderInfoLog (fragment_shader, buffer.len, &len, &buffer);
            std.debug.print ("ERROR: {}/{} {s}\n", .{buffer.len, len, buffer[0..@intCast (len)]});
            std.debug.print ("----\n{s}\n----\n", .{fragment_source.items});
            return error.FragmentCompilationFailed;
        }

        const id = gl.createProgram ();
        gl.attachShader (id, vertex_shader);
        gl.attachShader (id, fragment_shader);
        gl.linkProgram (id);

        gl.getProgramiv (id, gl.LINK_STATUS, &success);
        if (success == 0)
        {
            var buffer : [512]u8 = undefined;
            var len : c_int = undefined;
            gl.getProgramInfoLog (fragment_shader, buffer.len, &len, &buffer);
            std.debug.print ("ERROR: {}/{} {s}\n", .{buffer.len, len, buffer[0..@intCast (len)]});
            return error.ShaderLinkFailed;
        }
        gl.deleteShader (vertex_shader);
        gl.deleteShader (fragment_shader);
        return .{
            .id = id
        };
    }

    pub fn use (self: Shader) void
    {
        gl.useProgram (self.id);
    }
};

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
