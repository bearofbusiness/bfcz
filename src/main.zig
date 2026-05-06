const std = @import("std");
const cla = @import("cla");

pub fn main(init: std.process.Init) !void {
    // setup constants
    const allocator = init.arena.allocator();

    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    const options = cla.parse(args) catch |err| {
        cla.usage(args[0]);

        if (err == error.HelpRequested) return;

        std.debug.print("\nerror: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    // if (options.inputIsStdin()) {
    //     std.debug.print("input: stdin\n", .{});
    //     // Stdin
    // } else {
    //     std.debug.print("input: {s}\n", .{options.input});
    //     // Has real input
    // }

    // std.debug.print("output: {s}\n", .{options.output});
    // std.debug.print("optimization: {}\n", .{options.optimization});
    // std.debug.print("preprocessing: {}\n", .{options.preprocessing});
    // std.debug.print("print asm: {}\n", .{options.print_asm});
    //std.debug.print("extension.syscalls: {}\n", .{options.extensions.syscalls});

    // convert to absolute path
    const cwd = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd);

    var input: *std.Io.Reader = undefined;
    var input_path: []u8 = undefined;
    if (options.inputIsStdin()) {
        var input_buffer: [1024]u8 = undefined;
        var input_reader: std.Io.File.Reader = .init(.stdin(), io, &input_buffer);
        input = &input_reader.interface;
    } else {
        input_path = try std.Io.Dir.path.resolve(allocator, &.{ cwd, options.input });
        var input_file = try std.Io.Dir.openFileAbsolute(io, input_path, .{ .mode = .read_only });
        var input_buffer: [1024]u8 = undefined;
        var input_reader = input_file.reader(io, &input_buffer);
        input = &input_reader.interface;
    }
    defer if (!options.inputIsStdin()) allocator.free(input_path);

    const output_path = try std.Io.Dir.path.resolve(allocator, &.{ cwd, options.output });
    defer allocator.free(output_path);

    //do not need to create one until I actually write the binary myself
    //var output_file = try std.Io.Dir.createFileAbsolute(io, output_path, .{});

    const asm_output_path = try std.fmt.allocPrint(allocator, "{s}.s", .{output_path});
    defer allocator.free(asm_output_path);

    var asm_output_file = try std.Io.Dir.createFileAbsolute(io, asm_output_path, .{});
    var asm_output_buffer: [1024]u8 = undefined;
    var asm_output_writer = asm_output_file.writer(io, &asm_output_buffer);
    const asm_output = &asm_output_writer.interface;

    // compile
    if (options.print_asm) {
        try compileBF(stdout, allocator, input, options.optimization, options.extensions);
    }
    // compile twice because I'm evil
    try compileBF(asm_output, allocator, input, options.optimization, options.extensions);
    try asm_output.flush();
    try stdout.flush();

    try assembleWithZig(allocator, io, asm_output_path, output_path);

    // always remember to flush!
    try stdout.flush();
}

pub fn compileBF(writer: *std.Io.Writer, allocator: std.mem.Allocator, input: *std.Io.Reader, optimize: bool, extensions: cla.ExtensionSubOptions) !void {
    var label_id: usize = 0;
    var stack: std.ArrayList([2][]const u8) = .empty;
    defer stack.deinit(allocator);
    // set up tape + pointer
    try writer.print("    .intel_syntax noprefix\n", .{});
    try writer.print("    .section .bss\n", .{});
    try writer.print("    .lcomm tape, 30000\n", .{}); // allocate 30,000 bytes
    try writer.print("    .section .text\n", .{});
    try writer.print("    .globl main\n", .{});
    try writer.print("main:\n", .{});
    // disable canonical+echo via ioctl
    try writer.print("    sub  rsp, 64             # alloc termios buffer\n", .{});
    try writer.print("    mov  rax, 16             # SYS_ioctl\n", .{});
    try writer.print("    mov  rdi, 0              # fd = stdin\n", .{});
    try writer.print("    mov  rsi, 0x5401         # TCGETS\n", .{});
    try writer.print("    lea  rdx, [rsp]          # &orig_termios\n", .{});
    try writer.print("    syscall\n", .{});

    // clear ICANON(0x2) | ECHO(0x8) in c_lflag @ offset 12
    try writer.print("    mov  eax, dword ptr [rsp + 12]\n", .{});
    try writer.print("    and  eax,  ~(0x2 | 0x8)\n", .{});
    try writer.print("    mov  dword ptr [rsp + 12], eax\n", .{});

    try writer.print("    mov  rax, 16             # SYS_ioctl\n", .{});
    try writer.print("    mov  rdi, 0              # fd = stdin\n", .{});
    try writer.print("    mov  rsi, 0x5402         # TCSETS\n", .{});
    try writer.print("    lea  rdx, [rsp]          # &modified_termios\n", .{});
    try writer.print("    syscall\n", .{});

    // now r12 = tape
    try writer.print("    lea  r12, [rip + tape]   # r12 = &tape\n", .{});

    var c: u8 = try readCharOrElseZero(input, allocator);
    while (c != 0) : (c = try readCharOrElseZero(input, allocator)) {
        if (c == '>') {
            var optimize_n: usize = 0;
            if (optimize) {
                optimize_n = try optimizeRepitition('>', input);
            }
            if (optimize_n == 0) {
                try writer.print("    inc r12\n", .{});
            } else {
                try writer.print("    add r12, {d}\n", .{optimize_n + 1});
            }
        } else if (c == '<') {
            var optimize_n: usize = 0;
            if (optimize) {
                optimize_n = try optimizeRepitition('<', input);
            }
            if (optimize_n == 0) {
                try writer.print("    dec r12\n", .{});
            } else {
                try writer.print("    sub r12, {d}\n", .{optimize_n + 1});
            }
        } else if (c == '+') {
            var optimize_n: usize = 0;
            if (optimize) {
                optimize_n = try optimizeRepitition('+', input);
            }
            if (optimize_n == 0) {
                try writer.print("    inc byte ptr [r12]\n", .{});
            } else {
                try writer.print("    add byte ptr [r12], {d}\n", .{optimize_n + 1});
            }
        } else if (c == '-') {
            var optimize_n: usize = 0;
            if (optimize) {
                optimize_n = try optimizeRepitition('-', input);
            }
            if (optimize_n == 0) {
                try writer.print("    dec byte ptr [r12]\n", .{});
            } else {
                try writer.print("    sub byte ptr [r12], {d}\n", .{optimize_n + 1});
            }
        } else if (c == '.') {
            try writer.print("    mov rax, 1               # sys_write\n", .{});
            try writer.print("    mov rdi, 1               # stdout (fd=1)\n", .{});
            try writer.print("    mov rsi, r12             # buffer addr -> rsi\n", .{});
            try writer.print("    mov rdx, 1               # count=1\n", .{});
            try writer.print("    syscall\n", .{});
        } else if (c == ',') {
            try writer.print("    mov rax, 0               # sys_read\n", .{});
            try writer.print("    mov rdi, 0               # stdin\n", .{});
            try writer.print("    mov rsi, r12\n", .{});
            try writer.print("    mov rdx, 1\n", .{});
            try writer.print("    syscall\n", .{});
        } else if (c == '[') {
            const start = try std.fmt.allocPrint(allocator, comptime "L{d}", .{label_id});
            const end = try std.fmt.allocPrint(allocator, comptime "L{d}", .{label_id + 1});
            label_id += 2;
            try stack.append(allocator, .{ start, end });
            try writer.print("{s}:\n", .{start});
            try writer.print("    cmp byte ptr [r12], 0\n", .{});
            try writer.print("    je {s}\n", .{end});
        } else if (c == ']') {
            const locations: ?[2][]const u8 = stack.pop();
            if (locations == null) {
                @panic("Stack was empty square bracket mismatch extra ]");
            }
            try writer.print("    cmp byte ptr [r12], 0\n", .{});
            try writer.print("    jne {s}\n", .{locations.?[0]});
            try writer.print("{s}:\n", .{locations.?[1]});
            allocator.free(locations.?[0]);
            allocator.free(locations.?[1]);
        } else if (extensions.syscalls) {
            if (c == '$') {
                // 0..7     = rax
                // 8..15    = rdi
                // 16..23   = rsi
                // 24..31   = rdx
                // 32..39   = r10
                // 40..47   = r8
                // 48..55   = r9
                // 56..63   = return value
                try writer.print("    mov rax, qword ptr [r12 + 0]\n", .{});
                try writer.print("    mov rdi, qword ptr [r12 + 8]\n", .{});
                try writer.print("    mov rsi, qword ptr [r12 + 16]\n", .{});
                try writer.print("    mov rdx, qword ptr [r12 + 24]\n", .{});
                try writer.print("    mov r10, qword ptr [r12 + 32]\n", .{});
                try writer.print("    mov r8,  qword ptr [r12 + 40]\n", .{});
                try writer.print("    mov r9,  qword ptr [r12 + 48]\n", .{});

                try writer.print("    syscall\n", .{});

                try writer.print("    mov qword ptr [r12 + 56], rax\n", .{});
            } else if (c == '&') {
                // turn offset into pointer 64-bit
                try writer.print("    mov rax, qword ptr [r12]\n", .{});
                try writer.print("    add rax, r12\n", .{});
                try writer.print("    mov qword ptr [r12], rax\n", .{});
            }
        }
        // ignore other chars
    }
    // restore termios
    try writer.print("    mov  rax, 16             # SYS_ioctl\n", .{});
    try writer.print("    mov  rdi, 0              # fd = stdin\n", .{});
    try writer.print("    mov  rsi, 0x5402         # TCSETS\n", .{});
    try writer.print("    lea  rdx, [rsp]          # &orig_termios\n", .{});
    try writer.print("    syscall\n", .{});
    try writer.print("    add  rsp, 32             # free termios buffer\n", .{});

    // exit syscall
    try writer.print("    mov rax, 60              # sys_exit\n", .{});
    try writer.print("    xor rdi, rdi             # status=0\n", .{});
    try writer.print("    syscall\n", .{});

    if (stack.items.len != 0) {
        @panic("square bracket mismatch extra [");
    }
}

fn optimizeRepitition(char: u8, input: *std.Io.Reader) !usize {
    var cur = try peekBiteWithZero(input);
    var repitition: usize = 0;
    while (cur == char) : (cur = try peekBiteWithZero(input)) {
        _ = try input.takeByte();
        repitition += 1;
    }
    return repitition;
}

fn peekBiteWithZero(input: *std.Io.Reader) !u8 {
    return input.peekByte() catch |err| {
        if (err == std.Io.Reader.Error.EndOfStream) {
            return 0; // EOF
        } else {
            return err;
        }
    };
}

fn readCharOrElseZero(input: *std.Io.Reader, allocator: std.mem.Allocator) !u8 {
    const buf = input.readAlloc(allocator, 1) catch |err| {
        if (err == std.Io.Reader.Error.EndOfStream) {
            return 0; // EOF
        } else {
            return err;
        }
    };
    defer allocator.free(buf);
    if (buf.len == 0) {
        return 0; // EOF
    }
    return buf[0];
}

fn assembleWithZig(allocator: std.mem.Allocator, io: std.Io, asm_path: []const u8, out_path: []const u8) !void {
    const argv = [_][]const u8{
        "zig",
        "cc",
        "-target",
        "x86_64-linux-gnu",
        asm_path,
        "-o",
        out_path,
    };

    const result = try std.process.run(allocator, io, .{
        .argv = &argv,
        .stderr_limit = .limited(1024 * 1024),
        .stdout_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("zig cc failed with exit code {d}\n{s}\n", .{
                    code,
                    result.stderr,
                });
                return error.AssemblerFailed;
            }
        },
        else => |term| {
            std.debug.print("zig cc terminated abnormally: {any}\n{s}\n", .{
                term,
                result.stderr,
            });
            return error.AssemblerFailed;
        },
    }
}
