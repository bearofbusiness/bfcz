const std = @import("std");
const tokenizer = @import("tokenizer");
const parser = @import("parser");
const ReaderEOS = std.Io.Reader.Error.EndOfStream;

pub const Arg = union { int: isize };

pub const Macro = struct {
    macro: []const u8,
    args_len: usize,

    pub fn emmitMacro(this: Macro, writer: *std.Io.Writer, args: []const Arg) !void {
        _ = this;
        _ = writer;
        _ = args;
    }
};

pub fn preprocess(allocator: std.mem.Allocator, src: []const u8) ![]const u8 {
    var _tokenizer = tokenizer.Tokenizer.init(src);
    var tokens = try _tokenizer.tokenizeAll(allocator);
    defer tokens.deinit(allocator);

    _ = try parser.parse(tokens);

    return "";
}
