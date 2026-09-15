const std = @import("std");
const tokenizer = @import("tokenizer");

pub const ParserError = error {DangleingIdent, InvalidMacro};
pub const ParserAllocatorError = ParserError || std.mem.Allocator.Error;

pub const PatternTag = enum {
    plus,
    plus_with_ident,
    minus,
    minus_with_ident,
    ptr_left,
    ptr_left_with_ident,
    ptr_right,
    ptr_right_with_ident,
    print_deref_ptr,
    print_deref_ptr_with_ident,
    read_to_deref_ptr,
    read_to_deref_ptr_with_ident,
    open_loop,
    close_loop,
    get_offset_ptr,
    syscall,
    macro_call,
};

pub const Pattern = struct {
    token_tags: []tokenizer.TokenTag,
    pattern_tag: PatternTag,
    ident: ?[]const u8 = null,
    arguments: ?[]isize = null,

    fn deinit(self: Pattern, allocator: std.mem.Allocator) void {
        allocator.free(self.token_tags);
        if (self.ident) |ident|
            allocator.free(ident);
        if (self.arguments) |arg|
            allocator.free(arg);
    }
};

pub const ParsedCode = struct {
    pattern_array: []Pattern,
    macros: std.StringHashMap(Macro),

    pub fn deinit(self: *ParsedCode, allocator: std.mem.Allocator) void {
        for (self.pattern_array) |pat| {
            pat.deinit(allocator);
        }
        allocator.free(self.pattern_array);
        var itertator = self.macros.iterator();
        while (itertator.next()) |cur| {
            cur.value_ptr.deinit(allocator);
        }
        self.macros.deinit();
    }
};

pub fn parse(tokens: []tokenizer.Token, allocator: std.mem.Allocator) ParserAllocatorError!ParsedCode {
    var macros = std.StringHashMap(Macro).init(allocator);
    errdefer {
        var macro_iterator = macros.iterator();
        while (macro_iterator.next()) |macro| {
            macro.value_ptr.deinit(allocator);
        }
    }
    const parsed_code: ParsedCode = .{ .pattern_array = try parseRecursive(tokens, allocator, true, &macros, false), .macros = macros };
    return parsed_code;
}

fn parseRecursive(
    tokens: []tokenizer.Token,
    allocator: std.mem.Allocator,
    allow_macros: bool,
    macros: *std.StringHashMap(Macro),
    offset_allowed: bool,
) ![]Pattern { //replace with tree
    var pattern_array = std.ArrayList(Pattern).empty;
    errdefer {
        for (pattern_array.items) |item| {
            item.deinit(allocator);
        }
        pattern_array.deinit(allocator);
    }
    var i: usize = 0;
    while (i < tokens.len and tokens[i].tag != .eof) : (i += 1) {
        const cur = tokens[i].tag;
        if (allow_macros and cur == .macro_start) {
            i += try parseMacro(tokens[i..], macros, allocator);
        } else {
            switch (cur) {
                .plus => {
                    i += try createBasicPatternWithIdent(allocator, &pattern_array, tokens[i..], offset_allowed, .plus, .plus_with_ident);
                },
                .minus => {
                    i += try createBasicPatternWithIdent(allocator, &pattern_array, tokens[i..], offset_allowed, .minus, .minus_with_ident);
                },
                .comma => {
                    i += try createBasicPatternWithIdent(allocator, &pattern_array, tokens[i..], offset_allowed, .read_to_deref_ptr, .read_to_deref_ptr_with_ident);
                },
                .period => {
                    i += try createBasicPatternWithIdent(allocator, &pattern_array, tokens[i..], offset_allowed, .print_deref_ptr, .print_deref_ptr_with_ident);
                },
                //.left_paren => {},
                //.right_paren => {},
                .left_bracket => {
                    try createBasicPattern(allocator, &pattern_array, .open_loop);
                },
                .right_bracket => {
                    try createBasicPattern(allocator, &pattern_array, .close_loop);
                },
                //.left_brace => {},
                //.right_brace => {},
                .greater_than => {
                    i += try createBasicPatternWithIdent(allocator, &pattern_array, tokens[i..], offset_allowed, .ptr_right, .ptr_left_with_ident);
                },
                .less_than => {
                    i += try createBasicPatternWithIdent(allocator, &pattern_array, tokens[i..], offset_allowed, .ptr_left, .ptr_left_with_ident);
                },
                .ampersand => {
                    try createBasicPattern(allocator, &pattern_array, .get_offset_ptr);
                },
                .dollar_sign => {
                    try createBasicPattern(allocator, &pattern_array, .syscall);
                },
                .exclamation_point => {
                    i += try createMacroCallPattern(allocator, &pattern_array, tokens[i..], macros.*);
                }, // call macro,
                .ident => {
                    std.log.err("dangleing ident with name: {s}", .{tokens[i].text.?});
                    return ParserError.DangleingIdent;
                },
                else => {},
            }
        }
    }
    return pattern_array.items;
}
/// creates the pattern of basic funtions and repeated functions.
/// returns the number of tokens to eat(0 or 1).
fn createBasicPatternWithIdent(
    allocator: std.mem.Allocator,
    pattern_array: *std.ArrayList(Pattern),
    tokens: []tokenizer.Token,
    offset_allowed: bool,
    basic_tag: PatternTag,
    ident_tag: PatternTag,
) !usize {
    if (offset_allowed and tokens.len > 1 and tokens[1].tag == .ident) {
        const token_tags: []tokenizer.TokenTag = try allocator.alloc(tokenizer.TokenTag, 2);
        errdefer allocator.free(token_tags);

        token_tags[0] = tokens[0].tag;
        token_tags[1] = .ident;
        try pattern_array.append(allocator, .{ .token_tags = token_tags, .pattern_tag = ident_tag, .ident = try allocator.dupe(u8, tokens[1].text.?) });
        return 1;
    } else {
        try createBasicPattern(allocator, pattern_array, basic_tag);
    }
    return 0;
}

fn createBasicPattern(allocator: std.mem.Allocator, pattern_array: *std.ArrayList(Pattern), basic_tag: PatternTag) !void {
    const token_tags: []tokenizer.TokenTag = try allocator.alloc(tokenizer.TokenTag, 1);
    token_tags[0] = .plus;
    try pattern_array.append(allocator, .{ .token_tags = token_tags, .pattern_tag = basic_tag });
}

fn createMacroCallPattern(allocator: std.mem.Allocator, pattern_array: *std.ArrayList(Pattern), tokens: []tokenizer.Token, macros: std.StringHashMap(Macro)) !usize {
    var macro_pattern: Pattern = undefined;
    var token_tags = std.ArrayList(tokenizer.TokenTag).empty;
    errdefer token_tags.deinit(allocator);
    var i: usize = 3;
    if (tokens.len > 2 and tokens[0].tag == .exclamation_point and tokens[1].tag == .ident and tokens[2].tag == .left_paren) {
        if (!macros.contains(tokens[1].text.?)) {
            std.log.err("Invalid Macro Call: macro has not been initialized yet: {s}", .{tokens[1].text.?});
            return ParserError.InvalidMacro;
        }

        try token_tags.append(allocator, .exclamation_point);
        try token_tags.append(allocator, .ident);
        try token_tags.append(allocator, .left_paren);

        macro_pattern.ident = try allocator.dupe(u8, tokens[1].text.?);
        errdefer allocator.free(macro_pattern.ident.?);

        var args = std.ArrayList(isize).empty;
        errdefer args.deinit(allocator);
        while (i < tokens.len) : (i += 1) {
            const cur = tokens[i];
            if (cur.tag == .number) {
                try args.append(allocator, cur.int_value.?);
                try token_tags.append(allocator, .number);
            } else if (cur.tag == .right_paren) {
                try token_tags.append(allocator, .right_paren);
                break;
            } else {
                std.log.err("unknown token in macro({s}) arguments either missing right parethesis or using an invalid name for argument", .{tokens[1].text.?});
                return ParserError.InvalidMacro;
            }
        } else {
            std.log.err("eof in macro call: {s}", .{tokens[1].text.?});
            return ParserError.InvalidMacro;
        }
        macro_pattern.arguments = args.items;
        macro_pattern.token_tags = token_tags.items;
    } else {
        std.log.err("Invalid Macro Call: have fun! likely missing macro name or left parethesis", .{});
        return ParserError.InvalidMacro;
    }
    try pattern_array.append(allocator, macro_pattern);
    return i;
}

pub const Macro = struct {
    name: []const u8,
    args: std.ArrayList([]const u8),
    emission: []Pattern, // change later

    fn deinit(self: *Macro, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.args.items) |arg| {
            allocator.free(arg);
        }
        for (self.emission) |pat| {
            pat.deinit(allocator);
        }
    }
};

fn parseMacro(tokens: []tokenizer.Token, macros: *std.StringHashMap(Macro), allocator: std.mem.Allocator) ParserAllocatorError!usize {
    var macro: Macro = undefined;
    var i: usize = 3;
    if (tokens.len <= 2 or tokens[0].tag != .macro_start or tokens[1].tag != .ident or tokens[2].tag != .left_paren) {
        std.log.err("Invalid Macro: have fun! likely missing macro name or left parethesis", .{});
        return ParserError.InvalidMacro;
    }

    macro.name = tokens[1].text.?;
    while (i < tokens.len) : (i += 1) {
        var args = std.ArrayList([]const u8).empty;
        const cur = tokens[i];
        if (cur.tag == .ident) {
            try args.append(allocator, cur.text.?);
        } else if (cur.tag == .right_paren) {
            break;
        } else {
            std.log.err("unknown token in mecro({s}) arguments either missing right parethesis or using an invalid name for argument", .{tokens[1].text.?});
            return ParserError.InvalidMacro;
        }
    } else {
        std.log.err("eof in macro creation: {s}", .{tokens[1].text.?});
        return ParserError.InvalidMacro;
    }

    i += 1;
    if (tokens[i].tag != .left_brace) {
        std.log.err("missing left_brace at end of macro declareation: {s}", .{macro.name});
        return ParserError.InvalidMacro;
    }

    i += 1;
    const start: usize = i;
    var end: usize = 0;
    macro.emission = undefined;
    while (i < tokens.len and tokens[i].tag != .right_brace) : (i += 1) {
        end += 1;
        if (tokens[i].tag == .right_brace) break;
    } else {
        std.log.err("missing right brace at end of macro definition of: {s}", .{tokens[1].text.?});
        return ParserError.InvalidMacro;
    }

    macro.emission = try parseRecursive(tokens[start..end], allocator, false, macros, true);
    if (macros.contains(macro.name)) {
        
        var old_macro = macros.get(macro.name).?;
        _ = macros.remove(macro.name);
        old_macro.deinit(allocator);
    }

    try macros.put(macro.name, macro);
    return end;
}
