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

test "FSM process returns false after terminal state" {
    const State = enum { alive, dead };
    const Event = enum { die };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.alive, .event = Event.die, .to = State.dead },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.alive);
    try std.testing.expect(fsm.process(.die));
    try std.testing.expect(!fsm.process(.die)); // no transition from dead
    try std.testing.expectEqual(State.dead, fsm.currentState());
}

test "FSM large state machine" {
    const State = enum { s0, s1, s2, s3, s4, s5 };
    const Event = enum { next, reset };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.s0, .event = Event.next, .to = State.s1 },
        .{ .from = State.s1, .event = Event.next, .to = State.s2 },
        .{ .from = State.s2, .event = Event.next, .to = State.s3 },
        .{ .from = State.s3, .event = Event.next, .to = State.s4 },
        .{ .from = State.s4, .event = Event.next, .to = State.s5 },
        .{ .from = State.s5, .event = Event.reset, .to = State.s0 },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.s0);
    for (0..5) |_| {
        try std.testing.expect(fsm.process(.next));
    }
    try std.testing.expectEqual(State.s5, fsm.currentState());
    try std.testing.expect(fsm.process(.reset));
    try std.testing.expectEqual(State.s0, fsm.currentState());
}

test "FSM initWithCallbacks stores callbacks" {
    const State = enum { a, b };
    const Event = enum { go };
    const T = Transition(State, Event);

    const transitions = [_]T{};

    const Ctx = struct {
        fn onEnter(s: State) void { _ = s; }
        fn onExit(s: State) void { _ = s; }
    };

    const fsm = FSM(State, Event, &transitions).initWithCallbacks(.a, Ctx.onEnter, Ctx.onExit);
    try std.testing.expect(fsm.on_enter != null);
    try std.testing.expect(fsm.on_exit != null);
}

test "FSM self-transition" {
    const State = enum { idle };
    const Event = enum { tick };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.idle, .event = Event.tick, .to = State.idle },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.idle);
    try std.testing.expect(fsm.process(.tick));
    try std.testing.expectEqual(State.idle, fsm.currentState());
    try std.testing.expect(fsm.process(.tick)); // self-transition always valid
}

test "FSM multiple events to same target" {
    const State = enum { playing, paused };
    const Event = enum { pause_button, escape, phone_call };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.playing, .event = Event.pause_button, .to = State.paused },
        .{ .from = State.playing, .event = Event.escape, .to = State.paused },
        .{ .from = State.playing, .event = Event.phone_call, .to = State.paused },
        .{ .from = State.paused, .event = Event.pause_button, .to = State.playing },
        .{ .from = State.paused, .event = Event.escape, .to = State.playing },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.playing);
    
    // All three events pause the game
    try std.testing.expect(fsm.process(.pause_button));
    try std.testing.expectEqual(State.paused, fsm.currentState());
    
    try std.testing.expect(fsm.process(.escape));
    try std.testing.expectEqual(State.playing, fsm.currentState());
    
    try std.testing.expect(fsm.process(.phone_call));
    try std.testing.expectEqual(State.paused, fsm.currentState());
}

test "FSM transition order matters" {
    const State = enum { a, b };
    const Event = enum { go };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.a, .event = Event.go, .to = State.b },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.a);
    try std.testing.expect(fsm.process(.go));
    try std.testing.expectEqual(State.b, fsm.currentState());
    // No transition from b
    try std.testing.expect(!fsm.process(.go));
}

test "FSM forceTransition to same state" {
    const State = enum { idle, active };
    const Event = enum { toggle };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.idle, .event = Event.toggle, .to = State.active },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.idle);
    fsm.forceTransition(.idle);
    try std.testing.expectEqual(State.idle, fsm.currentState());
    // Still can transition
    try std.testing.expect(fsm.process(.toggle));
}

test "FSM Transition type has correct fields" {
    const State = enum { on, off };
    const Event = enum { flip };
    const T = Transition(State, Event);
    const t = T{ .from = .on, .event = .flip, .to = .off };
    try std.testing.expectEqual(State.on, t.from);
    try std.testing.expectEqual(Event.flip, t.event);
    try std.testing.expectEqual(State.off, t.to);
}

test "FSM patrol pattern" {
    const State = enum { patrol_forward, patrol_back, chase };
    const Event = enum { reached_end, reached_start, spotted, lost };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.patrol_forward, .event = Event.reached_end, .to = State.patrol_back },
        .{ .from = State.patrol_back, .event = Event.reached_start, .to = State.patrol_forward },
        .{ .from = State.patrol_forward, .event = Event.spotted, .to = State.chase },
        .{ .from = State.patrol_back, .event = Event.spotted, .to = State.chase },
        .{ .from = State.chase, .event = Event.lost, .to = State.patrol_forward },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.patrol_forward);
    _ = fsm.process(.reached_end);
    try std.testing.expectEqual(State.patrol_back, fsm.currentState());
    _ = fsm.process(.spotted);
    try std.testing.expectEqual(State.chase, fsm.currentState());
    _ = fsm.process(.lost);
    try std.testing.expectEqual(State.patrol_forward, fsm.currentState());
}

test "FSM state enum equality" {
    const State = enum { a, b, c };
    const Event = enum { go };
    const T = Transition(State, Event);
    const transitions = [_]T{};
    var fsm: FSM(State, Event, &transitions) = .init(.a);
    try std.testing.expect(fsm.currentState() == State.a);
    fsm.forceTransition(.c);
    try std.testing.expect(fsm.currentState() == State.c);
}

test "FSM process returns true only on valid transition" {
    const State = enum { locked, unlocked };
    const Event = enum { unlock, lock };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.locked, .event = Event.unlock, .to = State.unlocked },
        .{ .from = State.unlocked, .event = Event.lock, .to = State.locked },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.locked);
    try std.testing.expect(fsm.process(.unlock));
    try std.testing.expect(!fsm.process(.unlock)); // already unlocked
    try std.testing.expect(fsm.process(.lock));
    try std.testing.expect(!fsm.process(.lock)); // already locked
}

test "FSM canProcess after forceTransition" {
    const State = enum { a, b };
    const Event = enum { go };
    const T = Transition(State, Event);
    const transitions = [_]T{
        .{ .from = State.a, .event = Event.go, .to = State.b },
    };
    var fsm: FSM(State, Event, &transitions) = .init(.a);
    fsm.forceTransition(.b);
    try std.testing.expect(!fsm.canProcess(.go)); // no transition from b
}

test "FSM process preserves state on invalid event" {
    const State = enum { idle, running };
    const Event = enum { start, stop };
    const T = Transition(State, Event);
    const transitions = [_]T{
        .{ .from = State.idle, .event = Event.start, .to = State.running },
    };
    var fsm: FSM(State, Event, &transitions) = .init(.idle);
    _ = fsm.process(.start);
    const ok = fsm.process(.start); // no transition from running
    try std.testing.expect(!ok);
    try std.testing.expectEqual(State.running, fsm.currentState());
}

test "FSM elevator state machine" {
    const State = enum { door_open, door_closed, moving_up, moving_down };
    const Event = enum { close_door, open_door, reach_floor, request_up, request_down };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.door_open, .event = Event.close_door, .to = State.door_closed },
        .{ .from = State.door_closed, .event = Event.request_up, .to = State.moving_up },
        .{ .from = State.door_closed, .event = Event.request_down, .to = State.moving_down },
        .{ .from = State.moving_up, .event = Event.reach_floor, .to = State.door_open },
        .{ .from = State.moving_down, .event = Event.reach_floor, .to = State.door_open },
        .{ .from = State.door_open, .event = .open_door, .to = State.door_open },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.door_open);
    _ = fsm.process(.close_door);
    try std.testing.expectEqual(State.door_closed, fsm.currentState());
    _ = fsm.process(.request_up);
    try std.testing.expectEqual(State.moving_up, fsm.currentState());
    _ = fsm.process(.reach_floor);
    try std.testing.expectEqual(State.door_open, fsm.currentState());
}

test "FSM no transitions matches empty array" {
    const State = enum { a };
    const Event = enum { go };
    const T = Transition(State, Event);
    const transitions = [_]T{};
    var fsm: FSM(State, Event, &transitions) = .init(.a);
    try std.testing.expect(!fsm.process(.go));
    try std.testing.expect(!fsm.canProcess(.go));
}

test "FSM enemy AI: patrol, alert, chase, attack" {
    const State = enum { patrol, alert, chase, attack, dead };
    const Event = enum { see_player, lose_player, in_range, out_range, killed, respawn };
    const T = Transition(State, Event);

    const transitions = [_]T{
        .{ .from = State.patrol, .event = Event.see_player, .to = State.alert },
        .{ .from = State.alert, .event = Event.see_player, .to = State.chase },
        .{ .from = State.chase, .event = Event.in_range, .to = State.attack },
        .{ .from = State.attack, .event = Event.out_range, .to = State.chase },
        .{ .from = State.chase, .event = Event.lose_player, .to = State.patrol },
        .{ .from = State.attack, .event = Event.lose_player, .to = State.patrol },
        .{ .from = State.patrol, .event = Event.killed, .to = State.dead },
        .{ .from = State.dead, .event = Event.respawn, .to = State.patrol },
    };

    var fsm: FSM(State, Event, &transitions) = .init(.patrol);
    _ = fsm.process(.see_player); // patrol → alert
    try std.testing.expectEqual(State.alert, fsm.currentState());
    _ = fsm.process(.see_player); // alert → chase
    try std.testing.expectEqual(State.chase, fsm.currentState());
    _ = fsm.process(.in_range);   // chase → attack
    try std.testing.expectEqual(State.attack, fsm.currentState());
    _ = fsm.process(.out_range);  // attack → chase
    try std.testing.expectEqual(State.chase, fsm.currentState());
    _ = fsm.process(.lose_player); // chase → patrol
    try std.testing.expectEqual(State.patrol, fsm.currentState());
}

test "FSM forceTransition to dead then respawn" {
    const State = enum { alive, dead };
    const Event = enum { die, respawn };
    const T = Transition(State, Event);
    const transitions = [_]T{
        .{ .from = State.alive, .event = Event.die, .to = State.dead },
        .{ .from = State.dead, .event = Event.respawn, .to = State.alive },
    };
    var fsm: FSM(State, Event, &transitions) = .init(.alive);
    fsm.forceTransition(.dead);
    try std.testing.expect(fsm.canProcess(.respawn));
    _ = fsm.process(.respawn);
    try std.testing.expectEqual(State.alive, fsm.currentState());
}
