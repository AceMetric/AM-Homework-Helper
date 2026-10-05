#import "SSExitCoordinator.h"
@interface SSExitCoordinator ()
@property (readwrite) BOOL pending;
@property BOOL updating;
@property BOOL resolving;
@property (copy) void (^completion)(BOOL);
@end
@implementation SSExitCoordinator
- (void)requestForUpdate:(BOOL)updating completion:(void (^)(BOOL))completion {
    NSAssert(NSThread.isMainThread, @"Exit coordination must run on the main thread");
    if (self.pending) return;
    self.pending = YES; self.updating = updating; self.completion = completion;
    if (self.pauseOperations) self.pauseOperations(YES);
    if (self.cancelLogin) self.cancelLogin();
    // Do not reply to NSTerminateLater before applicationShouldTerminate returns.
    dispatch_async(dispatch_get_main_queue(), ^{ [self operationStateChanged]; });
}
- (void)operationStateChanged {
    if (!self.pending || self.resolving || (self.operationBusy && self.operationBusy())) return;
    self.resolving = YES;
    BOOL ready = !self.resolveEdits || self.resolveEdits(self.updating);
    self.resolving = NO;
    if (!ready) { [self cancel]; return; }
    // Saving a submission can start a new, explicitly requested Git operation.
    if (self.operationBusy && self.operationBusy()) return;
    if (self.persist && !self.persist()) { [self cancel]; return; }
    if (self.operationBusy && self.operationBusy()) return;
    void (^done)(BOOL) = self.completion; self.completion = nil; self.pending = NO;
    // Keep the gate closed until the application actually terminates.
    if (done) done(YES);
}
- (void)cancel {
    if (!self.pending) return;
    void (^done)(BOOL) = self.completion; self.completion = nil; self.pending = NO;
    if (self.pauseOperations) self.pauseOperations(NO);
    if (done) done(NO);
}
@end
