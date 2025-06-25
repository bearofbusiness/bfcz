const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var args = std.process.args();
    _ = args.skip();

    const file_path = args.next();
    if (file_path == null) {
        @panic("usage: bfcompiler program.bf");
    }

    const path = try std.fs.realpathAlloc(allocator, file_path.?[0..]);
    //std.debug.print("{s}", .{path});

    var file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });

    const input = try file.readToEndAlloc(allocator, @as(usize, 0) -% 1);

    try compileBF(stdout, allocator, input);

    try bw.flush();
}

pub fn compileBF(writer: anytype, allocator: std.mem.Allocator, input: []const u8) !void {
    var label_id: usize = 0;
    var stack: std.ArrayList([2][]const u8) = std.ArrayList([2][]const u8).init(allocator);
    // set up tape + pointer
    try writer.print("    .intel_syntax noprefix\n", .{});
    try writer.print("    .section .bss\n", .{});
    try writer.print("    .lcomm tape, 30000\n", .{}); // allocate 30,000 bytes
    try writer.print("    .section .text\n", .{});
    try writer.print("    .globl main\n", .{});
    try writer.print("main:\n", .{});
    // disable canonical+echo via ioctl
    try writer.print("    sub  rsp, 32              # alloc termios buffer\n", .{});
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
    try writer.print("    lea r12, [rip + tape]       # r12 = &tape\n", .{});

    for (input) |c| {
        if (c == '>') {
            try writer.print("    inc r12\n", .{});
        } else if (c == '<') {
            try writer.print("    dec r12\n", .{});
        } else if (c == '+') {
            try writer.print("    inc byte ptr [r12]\n", .{});
        } else if (c == '-') {
            try writer.print("    dec byte ptr [r12]\n", .{});
        } else if (c == '.') {
            try writer.print("    mov rax, 1         # sys_write\n", .{});
            try writer.print("    mov rdi, 1         # stdout (fd=1)\n", .{});
            try writer.print("    mov rsi, r12       # buffer addr -> rsi\n", .{});
            try writer.print("    mov rdx, 1         # count=1\n", .{});
            try writer.print("    syscall\n", .{});
        } else if (c == ',') {
            try writer.print("    mov rax, 0         # sys_read\n", .{});
            try writer.print("    mov rdi, 0         # stdin\n", .{});
            try writer.print("    mov rsi, r12\n", .{});
            try writer.print("    mov rdx, 1\n", .{});
            try writer.print("    syscall\n", .{});
        } else if (c == '[') {
            const start = try std.fmt.allocPrint(allocator, comptime "L{d}", .{label_id});
            const end = try std.fmt.allocPrint(allocator, comptime "L{d}", .{label_id + 1});
            label_id += 2;
            try stack.append(.{ start, end });
            try writer.print("{s}:\n", .{start});
            try writer.print("    cmp byte ptr [r12], 0\n", .{});
            try writer.print("    je {s}\n", .{end});
        } else if (c == ']') {
            const locations: ?[2][]const u8 = stack.pop();
            if (locations == null) {
                @panic("Stack was empty square bracket mismatch");
            }
            try writer.print("    cmp byte ptr [r12], 0\n", .{});
            try writer.print("    jne {s}\n", .{locations.?[0]});
            try writer.print("{s}:\n", .{locations.?[1]});
        }
        // ignore other chars
    }
    // restore termios
    try writer.print("    mov  rax, 16           # SYS_ioctl\n", .{});
    try writer.print("    mov  rdi, 0            # fd = stdin\n", .{});
    try writer.print("    mov  rsi, 0x5402       # TCSETS\n", .{});
    try writer.print("    lea  rdx, [rsp]        # &orig_termios\n", .{});
    try writer.print("    syscall\n", .{});
    try writer.print("    add  rsp, 32           # free termios buffer\n", .{});

    // exit syscall
    try writer.print("    mov rax, 60        # sys_exit\n", .{});
    try writer.print("    xor rdi, rdi       # status=0\n", .{});
    try writer.print("    syscall\n", .{});
}
