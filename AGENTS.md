# AGENTS.md

## Project: ziofsm

Finite state machine for game development. Written in Zig 0.16.

## Architecture
- `src/ziofsm.zig` — single-file library, all public API
- `examples/example.zig` — usage example
- `build.zig` — build configuration

## Commands
```bash
zig build test          # Run tests
zig build run-example   # Run example
zig fmt --check src/    # Check formatting
```

## Code Style
- Doc comments on all public symbols (`///`)
- Tests at the bottom of the source file
- No external dependencies
