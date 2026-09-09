const std = @import("std");
const tokenizer = @import("tokenizer");

const PatternValue = union {};

pub const Pattern = struct {};

pub const ParsedCode = struct {
    pattern_array: std.ArrayList(Pattern),
    macros: std.ArrayList(Macro),
};

pub fn parse(tokens: std.ArrayList(tokenizer.Token), allocator: std.mem.Allocator) !ParsedCode { //replace with tree
    var pattern_array = std.ArrayList(Pattern).empty;
    var macros = std.ArrayList(Macro).empty;
    var i: usize = 0;
    while (tokens.items[i].tag != .eof) : (i += 1) {
        if (tokens.items[i].tag == .macro_start) {
            parseMacro(tokens.items[i..], &macros, allocator);
        } else {
            switch (tokens.items[i].tag) {
                .plus => {},
                .minus => {},
                .comma => {},
                .left_paren => {},
                .right_paren => {},
                .left_bracket => {},
                .right_bracket => {},
                .left_brace => {},
                .right_brace => {},
                .exclamation_point => {},
                .greater_than => {},
                .less_than => {},
                .ampersand => {},
                .dollar_sign => {},
                .ident => {},
                else => {},
            }
        }
    }
}

pub const Macro = struct {
    number_of_args: usize,
    name: []const u8,
    args: std.ArrayList([]const u8),
    emission: std.ArrayList(Macro), // change later
};

const ParseMacroReturn = struct {
    eaten: usize,
    macro: Macro,
};
fn parseMacro(tokens: []tokenizer.Token, macros: *std.ArrayList(Macro), allocator: std.mem.Allocator) !ParseMacroReturn {
    var macro: Macro = undefined;
    var i: usize = 3;
    if(tokens.len > 2 and tokens[0].tag == .macro_start and tokens[1].tag == .ident and tokens[2].tag == .left_paren) {
        macro.name = tokens[1].text.?;
        while (i < tokens.len) : (i+=1) {
            var args = std.ArrayList([]const u8).empty;
            const cur = tokens[i];
            if (cur.tag == .ident) {
                args.append(allocator, cur.text);
            } else if (cur.tag == .right_paren) {
                break;
            } else {
                std.log.err("unknown token in mecro({s}) arguments either missing right parethesis or using an invalid name for argument", .{tokens[1].text});
                return error.InvalidMacro;
            }
        }
        i += 1;
        if (tokens[i].tag == .left_brace) {
            i += 1;
            while (tokens[i].tag != .right_brace) : (i += 1) {
                if (tokens[i].tag != .eof) {
                    std.log.err("unexpected eof within macro body: {s}", .{macro.text});
                    return error.InvalidMacro;
                }
            }
        } else {
            std.log.err("missing left_brace at end of macro declareation: {s}", .{macro.name});
        }

    } else {
        std.log.err("Invalid Macro: have fun! likely missing macro name or left parethesis", .{});
        return error.InvalidMacro;
    }

    macros.append(allocator, macro);
}
