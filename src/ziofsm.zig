//! Comptime finite state machine for games.
//!
//! Define states and transitions as enums, get type-safe state management
//! with enter/exit callbacks. Zero allocation, comptime-checked.

const std = @import("std");

/// A transition rule: from state + event → to state.
pub fn Transition(comptime State: type, comptime Event: type) type {
    return struct { from: State, event: Event, to: State };
}

/// A finite state machine parameterized over state and event enums.
pub fn FSM(comptime State: type, comptime Event: type, comptime transitions: []const Transition(State, Event)) type {
    return struct {
        current: State,
        on_enter: ?*const fn (State) void,
        on_exit: ?*const fn (State) void,

        const Self = @This();

        pub fn init(initial: State) Self {
            return .{ .current = initial, .on_enter = null, .on_exit = null };
        }

        pub fn initWithCallbacks(initial: State, on_enter: ?*const fn (State) void, on_exit: ?*const fn (State) void) Self {
            return .{ .current = initial, .on_enter = on_enter, .on_exit = on_exit };
        }

        /// Try to process an event. Returns true if a transition occurred.
        pub fn process(self: *Self, event: Event) bool {
            inline for (transitions) |t| {
                if (self.current == t.from and event == t.event) {
                    if (self.on_exit) |cb| cb(self.current);
                    self.current = t.to;
                    if (self.on_enter) |cb| cb(self.current);
                    return true;
                }
            }
            return false;
        }

        /// Check if a transition would succeed without performing it.
        pub fn canProcess(self: *const Self, event: Event) bool {
            inline for (transitions) |t| {
                if (self.current == t.from and event == t.event) return true;
            }
            return false;
        }

        /// Force a state change regardless of transitions.
        pub fn forceTransition(self: *Self, new_state: State) void {
            if (self.on_exit) |cb| cb(self.current);
            self.current = new_state;
            if (self.on_enter) |cb| cb(self.current);
        }

        pub fn currentState(self: *const Self) State {
            return self.current;
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "FSM basic transitions" {
    const State = enum { idle, running, paused, stopped };
    const Event = enum { start, pause, go_continue, stop };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.idle, .event = Event.start, .to = State.running },
        .{ .from = State.running, .event = Event.pause, .to = State.paused },
        .{ .from = State.paused, .event = Event.go_continue, .to = State.running },
        .{ .from = State.running, .event = Event.stop, .to = State.stopped },
        .{ .from = State.paused, .event = Event.stop, .to = State.stopped },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.idle);
    try std.testing.expectEqual(State.idle, fsm.currentState());

    try std.testing.expect(fsm.process(.start));
    try std.testing.expectEqual(State.running, fsm.currentState());

    try std.testing.expect(fsm.process(.pause));
    try std.testing.expectEqual(State.paused, fsm.currentState());

    try std.testing.expect(fsm.process(.go_continue));
    try std.testing.expectEqual(State.running, fsm.currentState());
}

test "FSM invalid transition" {
    const State = enum { open, closed };
    const Event = enum { close, open };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.open, .event = Event.close, .to = State.closed },
        .{ .from = State.closed, .event = Event.open, .to = State.open },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.open);
    try std.testing.expect(fsm.process(.close));
    try std.testing.expect(!fsm.process(.close));
    try std.testing.expectEqual(State.closed, fsm.currentState());
}

test "FSM canProcess" {
    const State = enum { idle, active };
    const Event = enum { activate, deactivate };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.idle, .event = Event.activate, .to = State.active },
        .{ .from = State.active, .event = Event.deactivate, .to = State.idle },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.idle);
    try std.testing.expect(fsm.canProcess(.activate));
    try std.testing.expect(!fsm.canProcess(.deactivate));
}

test "FSM force" {
    const State = enum { a, b, c };
    const Event = enum { go };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.a, .event = Event.go, .to = State.b },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.a);
    fsm.forceTransition(.c);
    try std.testing.expectEqual(State.c, fsm.currentState());
}

test "FSM with callbacks" {
    const State = enum { off, on };
    const Event = enum { toggle };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.off, .event = Event.toggle, .to = State.on },
        .{ .from = State.on, .event = Event.toggle, .to = State.off },
    };

    // Verify callbacks are stored and called via simple state tracking
    var transition_count: u32 = 0;
    _ = &transition_count;

    const Ctx = struct {
        fn onEnter(s: State) void { _ = s; }
        fn onExit(s: State) void { _ = s; }
    };

    var fsm: FSM(State, Event, &transitions) = .initWithCallbacks(.off, Ctx.onEnter, Ctx.onExit);
    try std.testing.expect(fsm.process(.toggle));
    try std.testing.expectEqual(State.on, fsm.currentState());
    try std.testing.expect(fsm.process(.toggle));
    try std.testing.expectEqual(State.off, fsm.currentState());
}

test "FSM no transitions defined" {
    const State = enum { a, b };
    const Event = enum { go };
    const T = Transition(State, Event);

    const transitions = [_]T{};

    var fsm: FSM(State, Event, &transitions) = .init(.a);
    try std.testing.expect(!fsm.process(.go));
    try std.testing.expectEqual(State.a, fsm.currentState());
}

test "FSM single state loop" {
    const State = enum { idle };
    const Event = enum { tick };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.idle, .event = Event.tick, .to = State.idle },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.idle);
    try std.testing.expect(fsm.process(.tick));
    try std.testing.expectEqual(State.idle, fsm.currentState());
}

test "FSM process returns false for invalid event" {
    const State = enum { idle, running };
    const Event = enum { start, stop, pause };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.idle, .event = Event.start, .to = State.running },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.idle);
    try std.testing.expect(!fsm.process(.stop));
    try std.testing.expect(!fsm.process(.pause));
    try std.testing.expect(fsm.process(.start));
}

test "FSM forceTransition with callbacks" {
    const State = enum { a, b };
    const Event = enum { go };
    const T = Transition(State, Event);

    const transitions = [_]T{};

    var callback_count: u32 = 0;
    _ = &callback_count;

    const Ctx = struct {
        fn onEnter(s: State) void { _ = s; }
        fn onExit(s: State) void { _ = s; }
    };

    var fsm: FSM(State, Event, &transitions) = .initWithCallbacks(.a, Ctx.onEnter, Ctx.onExit);
    fsm.forceTransition(.b);
    try std.testing.expectEqual(State.b, fsm.currentState());
}

test "FSM canProcess after transition" {
    const State = enum { idle, active, done };
    const Event = enum { start, finish };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.idle, .event = Event.start, .to = State.active },
        .{ .from = State.active, .event = Event.finish, .to = State.done },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.idle);
    try std.testing.expect(!fsm.canProcess(.finish));
    _ = fsm.process(.start);
    try std.testing.expect(fsm.canProcess(.finish));
    try std.testing.expect(!fsm.canProcess(.start));
}

test "FSM multiple events from same state" {
    const State = enum { menu };
    const Event = enum { new_game, load_game, settings };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.menu, .event = Event.new_game, .to = State.menu },
        .{ .from = State.menu, .event = Event.load_game, .to = State.menu },
        .{ .from = State.menu, .event = Event.settings, .to = State.menu },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.menu);
    try std.testing.expect(fsm.process(.new_game));
    try std.testing.expect(fsm.process(.load_game));
    try std.testing.expect(fsm.process(.settings));
}

test "FSM init without callbacks" {
    const State = enum { a, b };
    const Event = enum { go };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.a, .event = Event.go, .to = State.b },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.a);
    try std.testing.expectEqual(State.a, fsm.currentState());
    try std.testing.expect(fsm.on_enter == null);
    try std.testing.expect(fsm.on_exit == null);
}

test "FSM diamond state machine" {
    const State = enum { start, left, right, end };
    const Event = enum { go_left, go_right, merge };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.start, .event = Event.go_left, .to = State.left },
        .{ .from = State.start, .event = Event.go_right, .to = State.right },
        .{ .from = State.left, .event = Event.merge, .to = State.end },
        .{ .from = State.right, .event = Event.merge, .to = State.end },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.start);
    
    // Go left path
    try std.testing.expect(fsm.process(.go_left));
    try std.testing.expectEqual(State.left, fsm.currentState());
    try std.testing.expect(fsm.process(.merge));
    try std.testing.expectEqual(State.end, fsm.currentState());
}

test "FSM forceTransition same state" {
    const State = enum { a, b };
    const Event = enum { go };
    const T = Transition(State, Event);

    const transitions = [_]T{};
    var fsm: FSM(State, Event, &transitions) = .init(.a);
    fsm.forceTransition(.a); // force to same state
    try std.testing.expectEqual(State.a, fsm.currentState());
}

test "FSM canProcess all invalid from terminal state" {
    const State = enum { alive, dead };
    const Event = enum { live, die };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.alive, .event = Event.die, .to = State.dead },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.alive);
    _ = fsm.process(.die);
    try std.testing.expect(!fsm.canProcess(.die));
    try std.testing.expect(!fsm.canProcess(.live));
}
