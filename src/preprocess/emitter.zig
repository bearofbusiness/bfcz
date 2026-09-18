const std = @import("std");
const tokenizer = @import("tokenizer");
const parser = @import("parser");

pub fn emittCode(allocator: std.mem.Allocator, parced_code: parser.ParsedCode) ![]const u8 {
    var emittion: std.ArrayList(u8) = .empty;
    errdefer emittion.deinit(allocator);

    try emittCodeRecursive(allocator, &emittion, parced_code.pattern_array, parced_code.macros, null);

    return emittion.items;//std.Io.Reader.fixed(emittion.items);
}

fn emittCodeRecursive(
    allocator: std.mem.Allocator,
    emittion: *std.ArrayList(u8),
    patterns: []parser.Pattern,
    macros: std.StringHashMap(parser.Macro),
    arguments: ?std.StringHashMap(isize),
) !void {
    for (patterns) |pattern| {
        switch (pattern.pattern_tag) {
            .open_loop => {
                try emittion.append(allocator, '[');
            },
            .close_loop => {
                try emittion.append(allocator, ']');
            },
            .get_offset_ptr => {
                try emittion.append(allocator, '&');
            },
            .minus => {
                try emittion.append(allocator, '-');
            },
            .plus => {
                try emittion.append(allocator, '+');
            },
            .ptr_left => {
                try emittion.append(allocator, '<');
            },
            .ptr_right => {
                try emittion.append(allocator, '>');
            },
            .print_deref_ptr => {
                try emittion.append(allocator, '.');
            },
            .read_to_deref_ptr => {
                try emittion.append(allocator, ',');
            },
            .syscall => {
                try emittion.append(allocator, '$');
            },
            .minus_with_ident => {
                try emittReversableWithIdent(allocator, emittion, arguments, pattern, '-', '+');
            },
            .plus_with_ident => {
                try emittReversableWithIdent(allocator, emittion, arguments, pattern, '+', '-');
            },
            .print_deref_ptr_with_ident => {
                try emittWithIdent(allocator, emittion, arguments, pattern, '.');
            },
            .read_to_deref_ptr_with_ident => {
                try emittWithIdent(allocator, emittion, arguments, pattern, ',');
            },
            .ptr_left_with_ident => {
                try emittReversableWithIdent(allocator, emittion, arguments, pattern, '<', '>');
            },
            .ptr_right_with_ident => {
                try emittReversableWithIdent(allocator, emittion, arguments, pattern, '>', '<');
            },
            .macro_call => {
                var args: std.StringHashMap(isize) = .init(allocator);

                var arg_names: [][]const u8 = undefined;
                var macro_patterns: []parser.Pattern = undefined;
                if (macros.get(pattern.ident.?)) |macro| {
                    arg_names = macro.args;
                    macro_patterns = macro.emission;
                } else {
                    std.log.err("unknown macro when called: {s}", .{pattern.ident.?});
                    return error.UnknownMacro;
                }

                if (arg_names.len != pattern.arguments.?.len) {
                    std.log.err("arg call arg length missmatch in macro_call: {s}, len_call: {d}, len_def: {d}", .{pattern.ident.?, pattern.arguments.?.len, arg_names.len});
                    return parser.ParserError.InvalidMacro;
                    
                }

                for (arg_names, pattern.arguments.?) |k, v| {
                    try args.put(k, v);
                }

                try emittCodeRecursive(allocator, emittion, macro_patterns, macros, args);
            },
        }
    }
}

fn emittReversableWithIdent(
    allocator: std.mem.Allocator,
    emittion: *std.ArrayList(u8),
    arguments: ?std.StringHashMap(isize),
    pattern: parser.Pattern,
    char: u8,
    reverse_char: u8,
) !void {
    if (arguments) |args| {
        const num = try replaceWithArgValue(args, pattern.ident.?);
        try emittion.appendNTimes(allocator, if (num > 0) char else reverse_char, @truncate(@abs(num)));
    } else {
        std.log.err("arguments are not allowed in context how did they get here?", .{});
    }
}

fn emittWithIdent(
    allocator: std.mem.Allocator,
    emittion: *std.ArrayList(u8),
    arguments: ?std.StringHashMap(isize),
    pattern: parser.Pattern,
    char: u8,
) !void {
    if (arguments) |args| {
        try emittion.appendNTimes(allocator, char, @truncate(@abs(try replaceWithArgValue(args, pattern.ident.?))));
    } else {
        std.log.err("arguments are not allowed in context how did they get here?", .{});
    }
}

fn replaceWithArgValue(arguments: std.StringHashMap(isize), ident: []const u8) !isize {
    return arguments.get(ident) orelse bk: {
        std.log.err("argument does not exist in context: {s}", .{ident});
        break :bk error.MacroDoesNotExist;
    };
}
