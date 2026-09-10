const std = @import("std");

pub const TokenTag = enum {
    ident,
    minus,
    plus,
    number,
    less_than,
    greater_than,
    left_bracket,
    right_bracket,
    left_brace,
    right_brace,
    exclamation_point,
    dollar_sign,
    ampersand,
    left_paren,
    right_paren,
    period,
    comma,
    macro_start,
    semicolon,
    eof,
};

// basic token wrapper
pub const Token = struct {
    tag: TokenTag,
    text: ?[]const u8 = null, //should always be allocated
    int_value: ?isize = null,
    pub fn format(self: Token, writer: std.Io.Writer) !void {
        if (self.text) |_text| {
            try writer.print("{s}:{s}", .{ @tagName(self.tag), _text });
        } else {
            if (self.int_value) |int| {
                try writer.print("{s}:{d}", .{ @tagName(self.tag), int });
            } else {
                try writer.print("{s}", .{@tagName(self.tag)});
            }
        }
    }
    pub fn deinit(self: Token, allocator: std.mem.Allocator) void {
        if (self.text) |text| {
            allocator.free(text);
        }
    }
};

pub const TokenList = struct {
    tokens: std.ArrayList(Token),
    pub fn deinit(self: *TokenList, allocator: std.mem.Allocator) void {
        for (self.tokens.items) |i| {
            i.deinit(allocator);
        }
        self.tokens.deinit(allocator);
    }
};

pub const Tokenizer = struct {
    src: []const u8,
    index: usize = 0,

    pub fn init(src: []const u8) Tokenizer {
        return .{
            .src = src,
            .index = 0,
        };
    }

    pub fn tokenizeAll(self: *Tokenizer, allocator: std.mem.Allocator) !TokenList {
        var out = try std.ArrayList(Token).initCapacity(allocator, 0);
        errdefer {
            for (out.items) |tok| {
                if (tok.text) |str| {
                    allocator.free(str);
                }
            }
            out.deinit(allocator);
        }
        while (true) {
            const tok = try self.nextToken(allocator);
            try out.append(allocator, tok);
            if (tok.tag == .eof) break;
        }
        return .{ .tokens = out };
    }

    fn nextToken(self: *Tokenizer, allocator: std.mem.Allocator) !Token {
        self.skipWhitespace();

        if (self.index >= self.src.len) {
            return .{ .tag = .eof };
        }

        //if (self.peekKeyword("let")) return try self.keywordToken(.let_kw, 3);
        //if (self.peekKeyword("if")) return try self.keywordToken(.if_kw, 2);
        //if (self.peekKeyword("while")) return try self.keywordToken(.while_kw, 5);
        //if (self.peekKeyword("print")) return try self.keywordToken(.print_kw, 5);

        if (self.peekKeyword("mac")) return try self.keywordToken(allocator, .macro_start, 3);

        //if (self.matchString("<-")) return .{ .tag = .move, .text = "<-" };

        const c = self.src[self.index];

        switch (c) {
            //'=' => return self.single(.equals),
            '+' => return try self.single(.plus, allocator),
            '-' => return try self.single(.minus, allocator),
            //';' => return try self.single(.semicolon, allocator),
            ',' => return try self.single(.comma, allocator),
            '(' => return try self.single(.left_paren, allocator),
            ')' => return try self.single(.right_paren, allocator),
            '[' => return try self.single(.left_bracket, allocator),
            ']' => return try self.single(.right_bracket, allocator),
            '{' => return try self.single(.left_brace, allocator),
            '}' => return try self.single(.right_brace, allocator),
            '!' => return try self.single(.exclamation_point, allocator),
            //'*' => return self.single(.mul, allocator),
            //'/' => return self.single(.div, allocator),
            //'%' => return self.single(.mod, allocator),
            '>' => return try self.single(.greater_than, allocator),
            '<' => return try self.single(.less_than, allocator),
            //'"' => return try self.readString(),
            //'\'' => return try self.readChar(),
            ';' => {
                while (self.src[self.index] != '\n') : (self.index += 1) {
                    if (self.index >= self.src.len) return .{ .tag = .eof };
                }
                return self.nextToken(allocator);
            },
            else => {},
        }

        if (std.ascii.isDigit(c)) {
            return try self.readNumber(allocator);
        }
        if (isIdentStart(c)) {
            return try self.readIdent(allocator);
        }
        std.log.err("{c}", .{self.src[self.index]});
        return error.BadCharacter;
    }

    fn single(self: *Tokenizer, tag: TokenTag, allocator: std.mem.Allocator) !Token {
        const start = self.index;
        self.index += 1;
        return .{ .tag = tag, .text = try allocator.dupe(u8, self.src[start .. start + 1]) };
    }

    fn keywordToken(self: *Tokenizer, allocator: std.mem.Allocator, tag: TokenTag, len: usize) !Token {
        const text = try allocator.dupe(u8, self.src[self.index .. self.index + len]);
        self.index += len;
        return .{ .tag = tag, .text = text };
    }

    fn peekKeyword(self: *Tokenizer, keyword: []const u8) bool {
        if (self.index + keyword.len > self.src.len) return false;
        if (!std.mem.eql(u8, self.src[self.index .. self.index + keyword.len], keyword)) return false;
        const end = self.index + keyword.len;
        if (end < self.src.len and isIdentContinue(self.src[end])) return false;
        return true;
    }

    fn matchString(self: *Tokenizer, needle: []const u8) bool {
        if (self.index + needle.len > self.src.len) return false;
        if (!std.mem.eql(u8, self.src[self.index .. self.index + needle.len], needle)) return false;
        self.index += needle.len;
        return true;
    }

    fn readNumber(self: *Tokenizer, allocator: std.mem.Allocator) !Token {
        const start = self.index;
        while (self.index < self.src.len and std.ascii.isDigit(self.src[self.index])) : (self.index += 1) {}
        const slice = self.src[start..self.index];
        const n = try std.fmt.parseInt(i32, slice, 10);
        return .{ .tag = .number, .text = try allocator.dupe(u8, slice), .int_value = n };
    }

    fn readIdent(self: *Tokenizer, allocator: std.mem.Allocator) !Token {
        const start = self.index;
        self.index += 1;
        while (self.index < self.src.len and isIdentContinue(self.src[self.index])) : (self.index += 1) {}
        const slice = self.src[start..self.index];
        const copy = try allocator.dupe(u8, slice);
        return .{ .tag = .ident, .text = copy };
    }

    fn readChar(self: *Tokenizer, allocator: std.mem.Allocator) !Token {
        // Python source accepts a single character like 'a'.
        if (self.index + 2 >= self.src.len) return error.UnterminatedChar;
        self.index += 1; // opening quote
        const value = self.src[self.index];
        self.index += 1;
        if (self.index >= self.src.len or self.src[self.index] != '\'') return error.UnterminatedChar;
        self.index += 1;
        const buf = try allocator.alloc(u8, 1);
        buf[0] = value;
        return .{ .tag = .char_lit, .text = buf, .int_value = @as(i32, value) };
    }

    fn readString(self: *Tokenizer, allocator: std.mem.Allocator) !Token {
        self.index += 1; // opening quote
        var bytes = try std.ArrayList(u8).initCapacity(allocator, 0);
        while (self.index < self.src.len) {
            const c = self.src[self.index];
            if (c == '"') {
                self.index += 1;
                const owned = try bytes.toOwnedSlice(allocator);
                return .{ .tag = .string_lit, .text = owned };
            }
            if (c == '\\') {
                self.index += 1;
                if (self.index >= self.src.len) return error.UnterminatedString;
                const esc = self.src[self.index];
                const decoded: u8 = switch (esc) {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '\\' => '\\',
                    '"' => '"',
                    else => esc,
                };
                try bytes.append(allocator, decoded);
                self.index += 1;
                continue;
            }
            try bytes.append(allocator, c);
            self.index += 1;
        }
        return error.UnterminatedString;
    }

    fn skipWhitespace(self: *Tokenizer) void {
        while (self.index < self.src.len and std.ascii.isWhitespace(self.src[self.index])) : (self.index += 1) {}
    }

    fn isIdentStart(c: u8) bool {
        return std.ascii.isAlphabetic(c) or c == '_';
    }

    fn isIdentContinue(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_';
    }
};

test "tokenization test" {
    const str: []const u8 =
        \\mac cpy(a b c){
        \\    >a[-<a>c+<c>b+<b>a]<a>c[-<c>a+<a>c]
        \\}
        \\
        \\>++<!cpy(1 0 2)
    ;
    const allocator: std.mem.Allocator = std.testing.allocator;

    var tokenizer: Tokenizer = Tokenizer.init(str);

    var tok_list: TokenList = try tokenizer.tokenizeAll(allocator);

    const tok = tok_list.tokens;

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

    tok_list.deinit(allocator);
}
