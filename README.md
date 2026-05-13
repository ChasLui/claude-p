# claude-p

> **Use at your own risk.** This package and repository exist for
> **educational purposes** — to demonstrate why client-side restrictions
> on how a product is used are fundamentally unenforceable. If a CLI is
> on your machine, you can drive it.

A drop-in replacement for `claude -p` that drives the interactive
`claude` UI inside an in-process [zmux][zmux] PTY session.

[zmux]: https://github.com/smithersai/zmux

## Use

```bash
npx claude-p "your prompt here"
```

Output on stdout matches `claude -p` byte-for-byte.

## Flags

```
--output-format <text|json|stream-json>   default: text
--model <name>
--max-turns <N>
--allowedTools <list>
--dangerously-skip-permissions
--resume <id> | --continue | --session-id <uuid>
--cwd <path>
--input-file <path>
--verbose
--timeout <seconds>                       default: 300
--debug
```

Unrecognized flags are forwarded to `claude`.

## Requirements

- macOS or Linux (x64 or arm64)
- `claude` CLI on `$PATH`

## From source

```bash
git clone https://github.com/smithersai/claude-p
cd claude-p
zig build -Doptimize=ReleaseSafe
```

Requires Zig **0.15.2**.

## License

MIT.
