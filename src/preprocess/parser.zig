const std = @import("std");
const tokenizer = @import("tokenizer");

const PatternValue = union {};

pub const PatternTag = enum {
    plus,
    plus_with_ident,
    minus,
    minus_with_ident,
    ptr_left,
    ptr_left_with_ident,
    ptr_right,
    ptr_right_with_ident,
};

pub const Pattern = struct {
    token_tags: []tokenizer.TokenTag,

    fn deinit(self: Pattern, allocator: std.mem.Allocator) void {
        allocator.free(self.token_tags);
    }
};

pub const ParsedCode = struct {
    pattern_array: std.ArrayList(Pattern),
    macros: *std.ArrayList(Macro),
};

pub fn parse(tokens: []tokenizer.Token, allocator: std.mem.Allocator) !ParsedCode {
    var macros = std.AutoHashMap([]const u8, Macro).init(allocator);
    return try parseRecursive(tokens, allocator, true, &macros);
}

fn parseRecursive(tokens: []tokenizer.Token, allocator: std.mem.Allocator, allow_macros: bool, macros: *std.AutoHashMap([]const u8, Macro), offset_allowed: bool) !ParsedCode { //replace with tree
    var pattern_array = std.ArrayList(Pattern).empty;
    var i: usize = 0;
    while (i < tokens.len and tokens[i].tag != .eof) : (i += 1) {
        const cur = tokens[i].tag;
        if (allow_macros and cur == .macro_start) {
            i += parseMacro(tokens[i..], macros, allocator);
        } else {
            switch (cur) {
                .plus => {
                    if (offset_allowed and tokens[i + 1].tag == .ident) {
                        const token_tags: []tokenizer.TokenTag = try allocator.alloc(tokenizer.TokenTag, 2);
                        token_tags[0] = .plus;
                        token_tags[1] = .ident;
                        pattern_array.append(allocator, .{ .token_tags = token_tags });
                        i += 1;
                    } else {
                        const token_tags: []tokenizer.TokenTag = try allocator.alloc(tokenizer.TokenTag, 1);
                        token_tags[0] = .plus;
                        pattern_array.append(allocator, .{ .token_tags = token_tags });
                    }
                    continue;
                },
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
                .exclamation_point => {}, // call macro,
                .ident => {},
                else => {},
            }
        }
    }
}

pub const Macro = struct {
    name: []const u8,
    args: std.ArrayList([]const u8),
    emission: std.ArrayList(Pattern), // change later
};

fn parseMacro(tokens: []tokenizer.Token, macros: *std.AutoHashMap([]const u8, Macro), allocator: std.mem.Allocator) !usize {
    var macro: Macro = undefined;
    var i: usize = 3;
    if (tokens.len > 2 and tokens[0].tag == .macro_start and tokens[1].tag == .ident and tokens[2].tag == .left_paren) {
        macro.name = tokens[1].text.?;
        while (i < tokens.len) : (i += 1) {
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
            const start: usize = i;
            var end: usize = 0;
            macro.emission = .empty;
            while (i < tokens.len and tokens[i].tag != .right_brace) : (i += 1) {
                end += 1;
            }
            if (i >= tokens.len) {
                std.log.err("missing right brace at end of macro definition of: {s}", .{tokens[1].text});
                return error.InvalidMacro;
            }
            parseRecursive(tokens[start..end], allocator, false, macros);
        } else {
            std.log.err("missing left_brace at end of macro declareation: {s}", .{macro.name});
        }
    } else {
        std.log.err("Invalid Macro: have fun! likely missing macro name or left parethesis", .{});
        return error.InvalidMacro;
    }

    macros.put(macro.name, macro);
}
