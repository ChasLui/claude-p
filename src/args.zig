//! CLI argument parser. Mirrors a useful subset of `claude -p`'s surface
//! and forwards unknown flags through to the child `claude` invocation.
const std = @import("std");

pub const OutputFormat = enum {
    text,
    json,
    stream_json,

    pub fn fromString(s: []const u8) ?OutputFormat {
        if (std.mem.eql(u8, s, "text")) return .text;
        if (std.mem.eql(u8, s, "json")) return .json;
        if (std.mem.eql(u8, s, "stream-json")) return .stream_json;
        return null;
    }
};

pub const ParseError = error{
    BadOutputFormat,
    MissingValue,
    UnknownFlag,
    BadInteger,
    BadFloat,
    OutOfMemory,
};

pub const Options = struct {
    /// Heap-allocated; owns its strings.
    prompt: ?[]const u8 = null,
    /// Path to a file whose contents become the prompt (mutually exclusive with prompt).
    input_file: ?[]const u8 = null,
    output_format: OutputFormat = .text,
    model: ?[]const u8 = null,
    max_turns: ?u32 = null,
    allowed_tools: ?[]const u8 = null,
    dangerously_skip_permissions: bool = false,
    resume_session: ?[]const u8 = null,
    cont: bool = false,
    session_id: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    verbose: bool = false,
    timeout_seconds: u32 = 300,
    debug: bool = false,
    show_help: bool = false,
    show_version: bool = false,
    /// Arguments we don't recognize: passed through verbatim to `claude`.
    passthrough: std.ArrayList([]const u8) = .{},

    pub fn deinit(self: *Options, allocator: std.mem.Allocator) void {
        // Strings come from the original argv slice (caller-owned), so we
        // only need to free the passthrough list itself.
        self.passthrough.deinit(allocator);
    }
};

const help_text =
    \\Usage: claude-p [OPTIONS] [PROMPT]
    \\
    \\Emulates `claude -p` by driving the interactive `claude` binary inside
    \\an in-process libghostty terminal and capturing the final assistant
    \\message via a Stop hook.
    \\
    \\Options:
    \\  --output-format <fmt>           text | json | stream-json (default: text)
    \\  --model <name>                  Forwarded to `claude --model`
    \\  --max-turns <N>                 Abort after N assistant turns
    \\  --allowedTools <list>           Permission-rule list
    \\  --dangerously-skip-permissions  Bypass permission prompts
    \\  --resume <id>                   Resume a session
    \\  --continue, -c                  Continue the most recent session
    \\  --session-id <uuid>             Use a specific session UUID
    \\  --cwd <path>                    Working directory for `claude`
    \\  --input-file <path>             Read prompt from a file
    \\  --verbose                       Verbose output (required for stream-json)
    \\  --timeout <seconds>             Wrapper wall-time cap (default: 300)
    \\  --debug                         Wrapper debug logs to stderr
    \\  -h, --help                      Print this help
    \\  -v, --version                   Print version
    \\
    \\Unrecognized flags are forwarded verbatim to `claude`.
    \\
;

pub fn helpText() []const u8 {
    return help_text;
}

/// Parse argv (already stripped of argv[0]).
pub fn parse(allocator: std.mem.Allocator, argv: []const []const u8) ParseError!Options {
    var opts: Options = .{};
    errdefer opts.deinit(allocator);

    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];

        if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
            opts.show_help = true;
        } else if (std.mem.eql(u8, a, "-v") or std.mem.eql(u8, a, "--version")) {
            opts.show_version = true;
        } else if (std.mem.eql(u8, a, "--output-format")) {
            i += 1;
            if (i >= argv.len) return ParseError.MissingValue;
            opts.output_format = OutputFormat.fromString(argv[i]) orelse return ParseError.BadOutputFormat;
        } else if (std.mem.startsWith(u8, a, "--output-format=")) {
            opts.output_format = OutputFormat.fromString(a["--output-format=".len..]) orelse return ParseError.BadOutputFormat;
        } else if (std.mem.eql(u8, a, "--model")) {
            i += 1;
            if (i >= argv.len) return ParseError.MissingValue;
            opts.model = argv[i];
        } else if (std.mem.startsWith(u8, a, "--model=")) {
            opts.model = a["--model=".len..];
        } else if (std.mem.eql(u8, a, "--max-turns")) {
            i += 1;
            if (i >= argv.len) return ParseError.MissingValue;
            opts.max_turns = std.fmt.parseInt(u32, argv[i], 10) catch return ParseError.BadInteger;
        } else if (std.mem.eql(u8, a, "--allowedTools") or std.mem.eql(u8, a, "--allowed-tools")) {
            i += 1;
            if (i >= argv.len) return ParseError.MissingValue;
            opts.allowed_tools = argv[i];
        } else if (std.mem.eql(u8, a, "--dangerously-skip-permissions")) {
            opts.dangerously_skip_permissions = true;
        } else if (std.mem.eql(u8, a, "--resume")) {
            i += 1;
            if (i >= argv.len) return ParseError.MissingValue;
            opts.resume_session = argv[i];
        } else if (std.mem.eql(u8, a, "--continue") or std.mem.eql(u8, a, "-c")) {
            opts.cont = true;
        } else if (std.mem.eql(u8, a, "--session-id")) {
            i += 1;
            if (i >= argv.len) return ParseError.MissingValue;
            opts.session_id = argv[i];
        } else if (std.mem.eql(u8, a, "--cwd")) {
            i += 1;
            if (i >= argv.len) return ParseError.MissingValue;
            opts.cwd = argv[i];
        } else if (std.mem.eql(u8, a, "--input-file")) {
            i += 1;
            if (i >= argv.len) return ParseError.MissingValue;
            opts.input_file = argv[i];
        } else if (std.mem.eql(u8, a, "--verbose")) {
            opts.verbose = true;
        } else if (std.mem.eql(u8, a, "--debug")) {
            opts.debug = true;
        } else if (std.mem.eql(u8, a, "--timeout")) {
            i += 1;
            if (i >= argv.len) return ParseError.MissingValue;
            opts.timeout_seconds = std.fmt.parseInt(u32, argv[i], 10) catch return ParseError.BadInteger;
        } else if (std.mem.startsWith(u8, a, "--")) {
            // Unknown long option — forward (and absorb a value if next arg looks like one).
            try opts.passthrough.append(allocator, a);
            if (i + 1 < argv.len and !std.mem.startsWith(u8, argv[i + 1], "-")) {
                i += 1;
                try opts.passthrough.append(allocator, argv[i]);
            }
        } else if (std.mem.startsWith(u8, a, "-") and a.len > 1) {
            // Short flag — forward.
            try opts.passthrough.append(allocator, a);
        } else if (opts.prompt == null) {
            opts.prompt = a;
        } else {
            // Subsequent positionals: concat lazily by appending the second
            // (we expect only one positional).
            return ParseError.UnknownFlag;
        }
    }

    return opts;
}

// -------- tests --------

const testing = std.testing;

test "parse: empty argv" {
    var opts = try parse(testing.allocator, &.{});
    defer opts.deinit(testing.allocator);
    try testing.expectEqual(@as(?[]const u8, null), opts.prompt);
    try testing.expectEqual(OutputFormat.text, opts.output_format);
}

test "parse: positional prompt" {
    var opts = try parse(testing.allocator, &.{"hello world"});
    defer opts.deinit(testing.allocator);
    try testing.expectEqualStrings("hello world", opts.prompt.?);
}

test "parse: --output-format json" {
    var opts = try parse(testing.allocator, &.{ "--output-format", "json", "hi" });
    defer opts.deinit(testing.allocator);
    try testing.expectEqual(OutputFormat.json, opts.output_format);
    try testing.expectEqualStrings("hi", opts.prompt.?);
}

test "parse: --output-format=stream-json" {
    var opts = try parse(testing.allocator, &.{"--output-format=stream-json"});
    defer opts.deinit(testing.allocator);
    try testing.expectEqual(OutputFormat.stream_json, opts.output_format);
}

test "parse: bad output format" {
    try testing.expectError(ParseError.BadOutputFormat, parse(testing.allocator, &.{ "--output-format", "yaml" }));
}

test "parse: missing value after flag" {
    try testing.expectError(ParseError.MissingValue, parse(testing.allocator, &.{"--model"}));
}

test "parse: --max-turns" {
    var opts = try parse(testing.allocator, &.{ "--max-turns", "7" });
    defer opts.deinit(testing.allocator);
    try testing.expectEqual(@as(?u32, 7), opts.max_turns);
}

test "parse: bad integer" {
    try testing.expectError(ParseError.BadInteger, parse(testing.allocator, &.{ "--max-turns", "seven" }));
}

test "parse: --dangerously-skip-permissions" {
    var opts = try parse(testing.allocator, &.{"--dangerously-skip-permissions"});
    defer opts.deinit(testing.allocator);
    try testing.expect(opts.dangerously_skip_permissions);
}

test "parse: --continue alias -c" {
    var opts1 = try parse(testing.allocator, &.{"--continue"});
    defer opts1.deinit(testing.allocator);
    try testing.expect(opts1.cont);
}

test "parse: unknown long flag is forwarded" {
    var opts = try parse(testing.allocator, &.{ "--frobnitz", "bar", "hello" });
    defer opts.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 2), opts.passthrough.items.len);
    try testing.expectEqualStrings("--frobnitz", opts.passthrough.items[0]);
    try testing.expectEqualStrings("bar", opts.passthrough.items[1]);
    try testing.expectEqualStrings("hello", opts.prompt.?);
}

test "parse: --help" {
    var opts = try parse(testing.allocator, &.{"--help"});
    defer opts.deinit(testing.allocator);
    try testing.expect(opts.show_help);
}

test "parse: --version" {
    var opts = try parse(testing.allocator, &.{"-v"});
    defer opts.deinit(testing.allocator);
    try testing.expect(opts.show_version);
}

test "parse: --timeout" {
    var opts = try parse(testing.allocator, &.{ "--timeout", "60", "hi" });
    defer opts.deinit(testing.allocator);
    try testing.expectEqual(@as(u32, 60), opts.timeout_seconds);
}

test "parse: --resume value" {
    var opts = try parse(testing.allocator, &.{ "--resume", "550e8400-e29b-41d4-a716-446655440000" });
    defer opts.deinit(testing.allocator);
    try testing.expectEqualStrings("550e8400-e29b-41d4-a716-446655440000", opts.resume_session.?);
}

test "parse: --input-file" {
    var opts = try parse(testing.allocator, &.{ "--input-file", "/tmp/p.md" });
    defer opts.deinit(testing.allocator);
    try testing.expectEqualStrings("/tmp/p.md", opts.input_file.?);
}
