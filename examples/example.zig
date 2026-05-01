const std = @import("std");
const ziofsm = @import("ziofsm");

pub fn main() !void {
    const State = enum { menu, playing, paused, game_over };
    const Event = enum { start, pause, go_continue, die, reset };
    const T = ziofsm.Transition(State, Event);

    const transitions = [_]T{
        .{ .from = .menu, .event = .start, .to = .playing },
        .{ .from = .playing, .event = .pause, .to = .paused },
        .{ .from = .paused, .event = .go_continue, .to = .playing },
        .{ .from = .playing, .event = .die, .to = .game_over },
        .{ .from = .game_over, .event = .reset, .to = .menu },
    };

    var fsm: ziofsm.FSM(State, Event, &transitions) = .init(.menu);
    std.debug.print("State: {}\n", .{fsm.currentState()});

    _ = fsm.process(.start);
    std.debug.print("After start: {}\n", .{fsm.currentState()});

    _ = fsm.process(.die);
    std.debug.print("After die: {}\n", .{fsm.currentState()});

    _ = fsm.process(.reset);
    std.debug.print("After reset: {}\n", .{fsm.currentState()});
}
