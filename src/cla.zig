const std = @import("std");

pub const Options = struct {
    /// "-" means stdin.
    input: []const u8 = "-",
    output: []const u8 = "out",
    optimization: bool = false,
    preprocessing: bool = false,
    print_asm: bool = false,

    pub fn inputIsStdin(self: Options) bool {
        return eq(self.input, "-");
    }
};

pub const ParseError = error{
    HelpRequested,
    MissingValue,
    UnknownArgument,
    DuplicateInput,
    DuplicateOutput,
    TooManyPositionals,
};

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn stripPrefix(s: []const u8, prefix: []const u8) ?[]const u8 {
    if (s.len < prefix.len) return null;
    if (!std.mem.eql(u8, s[0..prefix.len], prefix)) return null;
    return s[prefix.len..];
}

fn requireValue(args: []const []const u8, i: *usize) ParseError![]const u8 {
    i.* += 1;
    if (i.* >= args.len) return error.MissingValue;
    return args[i.*];
}

fn takePositional(
    options: *Options,
    saw_input: *bool,
    saw_output: *bool,
    value: []const u8,
) ParseError!void {
    if (!saw_input.*) {
        options.input = value;
        saw_input.* = true;
    } else if (!saw_output.*) {
        options.output = value;
        saw_output.* = true;
    } else {
        return error.TooManyPositionals;
    }
}

pub fn parse(args: []const []const u8) ParseError!Options {
    var options: Options = .{};
    var saw_input = false;
    var saw_output = false;

    // start at real args
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (eq(arg, "-h") or eq(arg, "--help")) {
            return error.HelpRequested;
        }

        if (eq(arg, "-i") or eq(arg, "--input")) {
            if (saw_input) return error.DuplicateInput;
            options.input = try requireValue(args, &i);
            saw_input = true;
            continue;
        }

        if (stripPrefix(arg, "--input=")) |value| {
            if (saw_input) return error.DuplicateInput;
            options.input = value;
            saw_input = true;
            continue;
        }

        if (eq(arg, "-o") or eq(arg, "--output")) {
            if (saw_output) return error.DuplicateOutput;
            options.output = try requireValue(args, &i);
            saw_output = true;
            continue;
        }

        if (stripPrefix(arg, "--output=")) |value| {
            if (saw_output) return error.DuplicateOutput;
            options.output = value;
            saw_output = true;
            continue;
        }

        if (eq(arg, "-O") or eq(arg, "--optimization") or eq(arg, "--optimize")) {
            options.optimization = true;
            continue;
        }

        if (eq(arg, "--no-optimization") or eq(arg, "--no-optimize")) {
            options.optimization = false;
            continue;
        }

        if (eq(arg, "-p") or eq(arg, "--preprocessing") or eq(arg, "--preprocess")) {
            options.preprocessing = true;
            continue;
        }

        if (eq(arg, "--no-preprocessing") or eq(arg, "--no-preprocess")) {
            options.preprocessing = false;
            continue;
        }

        if (eq(arg, "--print-asm")) {
            options.print_asm = true;
        }

        // Everything after "--" is positional, even if it starts with "-".
        if (eq(arg, "--")) {
            i += 1;
            while (i < args.len) : (i += 1) {
                try takePositional(&options, &saw_input, &saw_output, args[i]);
            }
            break;
        }

        if (arg.len > 0 and arg[0] == '-') {
            return error.UnknownArgument;
        }

        // bin input.txt output.txt -O -p
        try takePositional(&options, &saw_input, &saw_output, arg);
    }

    return options;
}

pub fn usage(program_name: []const u8) void {
    std.debug.print(
        \\Usage:
        \\  {s} [options]
        \\  {s} [input] [output] [options]
        \\
        \\Options:
        \\  -i, --input <path>         Input file. Use "-" for stdin. Default: "-"
        \\  -o, --output <path>        Output file. Default: "out"
        \\  -O, --optimization         Enable optimization
        \\      --optimize
        \\      --no-optimization      Disable optimization (default)
        \\      --no-optimize
        \\  -p, --preprocessing        Enable preprocessing
        \\      --preprocess
        \\      --no-preprocessing     Disable preprocessing (default)
        \\      --no-preprocess
        \\      --print-asm            Prints raw assembly for debug
        \\  -h, --help                 Show this help
        \\
        \\Examples:
        \\  {s} -i input.txt -o output.txt -O -p
        \\  {s} --input=input.txt -output=output.txt -O -p
        \\  cat input.txt | {s} -i - -o output.txt
        \\  cat input.txt | {s} -o output.txt
        \\
    , .{ program_name, program_name, program_name, program_name, program_name, program_name });
}
