const std = @import("std");
const tokenizer = @import("tokenizer");
const parser = @import("parser");
const emitter = @import("emitter");

pub fn preprocess(allocator: std.mem.Allocator, src: []const u8) ![]const u8 {
    var _tokenizer = tokenizer.Tokenizer.init(src);
    var tokens = try _tokenizer.tokenizeAll(allocator);
    defer tokens.deinit(allocator);

    var parced_code = try parser.parse(tokens.tokens.items, allocator);
    defer parced_code.deinit(allocator);
    const emitted_code = try emitter.emittCode(allocator, parced_code);

    return emitted_code;
}

test {
    const str: []const u8 =
        \\mac cpy(a b c){
        \\    >a[-<a>c+<c>b+<b>a]<a>c[-<c>a+<a>c]
        \\}
        \\
        \\>++<!cpy(1 0 2)
    ;
    const allocator: std.mem.Allocator = std.testing.allocator;

    var _tokenizer: tokenizer.Tokenizer = .init(str);

    var tok_list: tokenizer.TokenList = try _tokenizer.tokenizeAll(allocator);
    errdefer tok_list.deinit(allocator);

    const tok: std.ArrayList(tokenizer.Token) = tok_list.tokens;

    for (tok.items) |token| {
        if (token.text) |t| {
            std.log.warn("{s}:{s}", .{ @tagName(token.tag), t });
        } else {
            if (token.int_value) |int| {
                std.log.warn("{s}:{d}", .{ @tagName(token.tag), int });
            } else {
                std.log.warn("{s}", .{@tagName(token.tag)});
            }
        }
    }

    var parced_code = try parser.parse(tok.items, allocator);
    errdefer parced_code.deinit(allocator);
    tok_list.deinit(allocator);

    std.log.warn("\n\nMacros", .{});

    std.log.warn("macros:", .{});
    var itertator = parced_code.macros.iterator();
    while (itertator.next()) |cur| {
        std.log.warn("macro: {s}", .{cur.value_ptr.name});
        for (cur.value_ptr.args) |arg| {
            std.log.warn("arg: {s}", .{arg});
        }
    }

    std.log.warn("\nPatterns", .{});

    for (parced_code.pattern_array) |pattern| {
        std.log.warn("Pattern:{s}", .{@tagName(pattern.pattern_tag)});
        if (pattern.arguments) |args| {
            std.log.warn("args", .{});
            for (args) |arg| {
                std.log.warn("{d}", .{arg});
            }
        }
        std.log.warn("token_tags", .{});
        for (pattern.token_tags) |tag| {
            std.log.warn("{s}", .{@tagName(tag)});
        }
        if (pattern.ident) |ident|
            std.log.warn("ident: {s}", .{ident});

        std.log.warn("\n", .{});
    }

    std.log.warn("\n\n", .{});

    const emitted_code = try emitter.emittCode(allocator, parced_code);
    errdefer allocator.free(emitted_code);
    parced_code.deinit(allocator);

    std.log.warn("{s}", .{emitted_code});
    allocator.free(emitted_code);
}
