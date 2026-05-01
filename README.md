# ziofsm

> Comptime finite state machine for Zig games. Type-safe transitions, zero allocation.

Part of the [zio-zig](https://github.com/deblasis/zio-zig) ecosystem.

## Quick start

```zig
const zfsm = @import("ziofsm");

const State = enum { idle, walking, running, jumping };
const Event = enum { start_walk, stop, jump, land, speed_up };
const T = zfsm.Transition(State, Event);

const transitions = [_]T{
    .{ .from = .idle,    .event = .start_walk, .to = .walking },
    .{ .from = .walking, .event = .speed_up,   .to = .running },
    .{ .from = .running, .event = .stop,       .to = .idle },
    .{ .from = .walking, .event = .stop,       .to = .idle },
    .{ .from = .idle,    .event = .jump,       .to = .jumping },
    .{ .from = .walking, .event = .jump,       .to = .jumping },
    .{ .from = .jumping, .event = .land,       .to = .idle },
};

var fsm = zfsm.FSM(State, Event, &transitions).init(.idle);

// Process events
fsm.process(.start_walk);  // idle → walking
fsm.process(.speed_up);    // walking → running
fsm.process(.jump);        // no transition! stays running
fsm.process(.stop);        // running → idle

// Query state
const state = fsm.currentState();
const can_jump = fsm.canProcess(.jump);
```

```bash
zig build test          # Run 39 tests
zig build run-example   # Run example
```

## Example output

```
$ zig build run-example
State: .menu
After start: .playing
After die: .game_over
After reset: .menu
```

## API

### Transition(State, Event)

Struct with `.from: State`, `.event: Event`, `.to: State`.

### FSM(State, Event, transitions)

Comptime-parameterized state machine. Transitions array is comptime-known.

| Method | Description |
|--------|-------------|
| `init(initial_state)` | Create FSM in initial state |
| `process(event)` | Process event, returns `true` if transition occurred |
| `canProcess(event)` | Check if a transition exists for current state + event |
| `currentState()` | Get current state |
| `forceTransition(state)` | Jump to any state (bypass transitions) |

### Properties
- Zero allocation — all state stored inline
- Comptime-verified — transition table checked at compile time
- `process()` returns false for invalid transitions (no state change)

## License

MIT. Copyright (c) 2026 Alessandro De Blasis.
