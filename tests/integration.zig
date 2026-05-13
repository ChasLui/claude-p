//! Integration tests against the real `claude` binary.
//!
//! These tests are skipped by default. Enable with `CLAUDE_P_E2E=1`:
//!
//!     CLAUDE_P_E2E=1 zig build test-integration
//!
//! No mocks. We invoke the actual `claude` on $PATH and assert the wrapper's
//! output looks like what `claude -p` would emit for the same prompt.
const std = @import("std");
const claude_p = @import("claude_p");

fn e2eEnabled() bool {
    return std.process.hasEnvVar(std.heap.page_allocator, "CLAUDE_P_E2E") catch false;
}

test "real claude: text output for trivial prompt" {
    if (!e2eEnabled()) return error.SkipZigTest;

    var result = try claude_p.run(std.testing.allocator, .{
        .prompt = "Reply with the single word OK and nothing else.",
        .output_format = .text,
        .timeout_ms = 90_000,
        .skip_permissions = true,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.summary.final_text.len > 0);
    try std.testing.expect(!result.summary.is_error);
}

test "real claude: json output round-trips through std.json" {
    if (!e2eEnabled()) return error.SkipZigTest;

    var result = try claude_p.run(std.testing.allocator, .{
        .prompt = "Reply with the single word OK and nothing else.",
        .output_format = .json,
        .timeout_ms = 90_000,
        .skip_permissions = true,
    });
    defer result.deinit(std.testing.allocator);

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    var aw = std.Io.Writer.Allocating.fromArrayList(std.testing.allocator, &buf);
    try result.write(std.testing.allocator, &aw.writer, .json);
    buf = aw.toArrayList();

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, buf.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("result", parsed.value.object.get("type").?.string);
    try std.testing.expect(parsed.value.object.get("session_id").?.string.len > 0);
}

test "real claude: exit code 0 on success" {
    if (!e2eEnabled()) return error.SkipZigTest;
    var result = try claude_p.run(std.testing.allocator, .{
        .prompt = "Reply with OK.",
        .timeout_ms = 90_000,
        .skip_permissions = true,
    });
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), result.exitCode());
}
