const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const DirectFundObjective = @import("directfund.zig").DirectFundObjective;

pub const ObjectiveId = types.ObjectiveId;
pub const ObjectiveType = types.ObjectiveType;
pub const ObjectiveStatus = types.ObjectiveStatus;
pub const WaitingFor = types.WaitingFor;
pub const SideEffect = types.SideEffect;
pub const CrankResult = types.CrankResult;
pub const ObjectiveEvent = types.ObjectiveEvent;

/// Generic Objective interface - all protocols implement this pattern
pub const Objective = union(ObjectiveType) {
    DirectFund: DirectFundObjective,
    DirectDefund: void, // TODO: Phase 4
    VirtualFund: void, // TODO: Phase 5
    VirtualDefund: void, // TODO: Phase 5

    pub fn id(self: Objective) ObjectiveId {
        return switch (self) {
            .DirectFund => |obj| obj.id,
            .DirectDefund, .VirtualFund, .VirtualDefund => unreachable,
        };
    }

    pub fn status(self: Objective) ObjectiveStatus {
        return switch (self) {
            .DirectFund => |obj| obj.status,
            .DirectDefund, .VirtualFund, .VirtualDefund => unreachable,
        };
    }

    pub fn waitingFor(self: Objective) WaitingFor {
        return switch (self) {
            .DirectFund => |obj| obj.waitingFor(),
            .DirectDefund, .VirtualFund, .VirtualDefund => unreachable,
        };
    }

    /// Pure function: compute state transitions and side effects
    /// Does not mutate self - returns new state via CrankResult
    pub fn crank(self: *Objective, event: ObjectiveEvent, a: Allocator) !CrankResult {
        return switch (self.*) {
            .DirectFund => |*obj| try obj.crank(event, a),
            .DirectDefund, .VirtualFund, .VirtualDefund => unreachable,
        };
    }

    pub fn deinit(self: Objective, a: Allocator) void {
        switch (self) {
            .DirectFund => |obj| obj.deinit(a),
            .DirectDefund, .VirtualFund, .VirtualDefund => {},
        }
    }
};
