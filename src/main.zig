const std = @import("std");

pub fn main(init: std.process.Init) !void {
pub fn main(init: std.process.Init) !void {
    // setup constants
    const allocator = init.arena.allocator();

    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    // init args and skip zig arg
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <file.bf>\n", .{args[0].ptr});
        return;
    }

    // convert to absolute path
    const cwd = try std.process.currentPathAlloc(io, allocator);
    const path = try std.Io.Dir.path.resolve(allocator, &.{ cwd, args[1] });

    // open file
    var file = try std.Io.Dir.openFileAbsolute(io, path, .{ .mode = .read_only });

    var read_buffer: [1024]u8 = undefined;
    var input_reader = file.reader(io, &read_buffer);
    const input = &input_reader.interface;

    // compile
    try compileBF(stdout, allocator, input);

    // always remember to flush!
    try stdout.flush();
}

pub fn compileBF(writer: anytype, allocator: std.mem.Allocator, input: *std.Io.Reader) !void {
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
    try writer.print("    sub  rsp, 32             # alloc termios buffer\n", .{});
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
            try writer.print("    inc r12\n", .{});
        } else if (c == '<') {
            try writer.print("    dec r12\n", .{});
        } else if (c == '+') {
            try writer.print("    inc byte ptr [r12]\n", .{});
        } else if (c == '-') {
            try writer.print("    dec byte ptr [r12]\n", .{});
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
