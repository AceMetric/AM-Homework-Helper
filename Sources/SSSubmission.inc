// Private sheet, shared controls. Only the captured course and selected paths leave this UI.
@interface SSSubmissionController : NSWindowController
@property NSArray *changes;
@property NSArray<NSButton *> *checks;
@property NSTextField *message;
@property NSTextField *validation;
@property NSTextView *preview;
@property (copy) void (^readPreview)(NSString *, void (^)(NSString *));
@property (copy) void (^submit)(NSArray *, NSString *);
@property NSUInteger previewGeneration;
- (instancetype)initWithCourse:(NSDictionary *)course changes:(NSArray *)changes;
@end
@implementation SSSubmissionController
- (instancetype)initWithCourse:(NSDictionary *)course changes:(NSArray *)changes {
    DDLFormPanel *panel = [[DDLFormPanel alloc] initWithContentRect:NSMakeRect(0, 0, 760, 580) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:panel])) {
        __weak typeof(self) weakSelf = self; panel.onConfirm = ^{ [weakSelf save:nil]; }; panel.onCancel = ^{ [weakSelf cancel:nil]; };
        self.changes = changes; panel.title = @"提交作业"; panel.releasedWhenClosed = NO;
        Surface *root = Box(Canvas(), 0); root.frame = NSMakeRect(0, 0, 760, 580); panel.contentView = root;
        Put(root, Text(@"提交作业", 23, NSFontWeightSemibold, Ink()), 24, 24, 712, 32);
        NSTextField *target = Text([NSString stringWithFormat:@"目标：%@ · %@", course[@"fork"], course[@"branch"]], 13, NSFontWeightMedium, Accent()); target.toolTip = target.stringValue; Put(root, target, 24, 64, 712, 24);
        Put(root, Text(@"逐项勾选文件。推送前会检查全部待推送提交。", 13, NSFontWeightRegular, Muted()), 24, 96, 712, 24);
        Put(root, Text(@"本次提交的文件", 13, NSFontWeightSemibold, Ink()), 24, 136, 304, 24);
        Put(root, Text(@"变更预览", 13, NSFontWeightSemibold, Ink()), 344, 136, 392, 24);
        Surface *list = Box(Card(), 8); list.frame = NSMakeRect(0, 0, 288, MAX(272, changes.count * 64)); NSMutableArray *checks = NSMutableArray.array;
        for (NSUInteger i = 0; i < changes.count; i++) {
            NSDictionary *change = changes[i]; NSButton *check = [NSButton checkboxWithTitle:change[@"path"] target:self action:@selector(selectionChanged:)]; check.tag = i; check.toolTip = change[@"path"]; check.state = NSControlStateValueOff; check.enabled = ![change[@"sensitive"] boolValue]; check.font = [NSFont systemFontOfSize:13]; Put(list, check, 8, i * 64 + 4, 272, 28); [checks addObject:check];
            ActionButton *view = Button(@"查看", self, @selector(showPreview:), 3); view.tag = i; Put(list, view, 220, i * 64 + 32, 60, 28);
            NSString *state = [change[@"sensitive"] boolValue] ? @"⚠ 敏感文件，已排除" : [NSString stringWithFormat:@"变更状态 %@", change[@"status"]]; Put(list, Text(state, 11, NSFontWeightRegular, Muted()), 8, i * 64 + 32, 204, 24);
        } self.checks = checks;
        NSScrollView *fileScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(24, 168, 304, 272)]; fileScroll.hasVerticalScroller = YES; fileScroll.autohidesScrollers = YES; fileScroll.drawsBackground = NO; fileScroll.documentView = list; [root addSubview:fileScroll];
        NSScrollView *previewScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(344, 168, 392, 272)]; previewScroll.hasVerticalScroller = YES; previewScroll.autohidesScrollers = YES;
        self.preview = [[PastelNotesView alloc] initWithFrame:NSMakeRect(0, 0, 372, 272)]; self.preview.editable = NO; self.preview.richText = NO; self.preview.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]; self.preview.textColor = Ink(); self.preview.backgroundColor = Card(); self.preview.textContainerInset = NSMakeSize(8, 8); self.preview.autoresizingMask = NSViewWidthSizable; self.preview.textContainer.widthTracksTextView = YES; self.preview.string = @"点击文件旁的“查看”检查变更。"; previewScroll.documentView = self.preview; [root addSubview:previewScroll];
        self.message = [[PastelTextField alloc] initWithFrame:NSZeroRect]; self.message.placeholderString = @"提交说明，例如：完成第四次物理作业"; self.message.accessibilityLabel = @"提交说明"; Put(root, self.message, 24, 456, 712, 36);
        self.validation = Text(@"尚未选择文件", 12, NSFontWeightRegular, Muted()); Put(root, self.validation, 24, 512, 400, 40);
        ActionButton *cancel = Button(@"取消", self, @selector(cancel:), 2); cancel.keyEquivalent = @"\033"; cancel.keyEquivalentModifierMask = 0; Put(root, cancel, 464, 520, 88, 36);
        ActionButton *save = Button(@"检查并提交", self, @selector(save:), 1); save.keyEquivalent = @"\r"; save.keyEquivalentModifierMask = 0; Put(root, save, 568, 520, 168, 36); panel.initialFirstResponder = self.message; panel.defaultButtonCell = save.cell;
    } return self;
}
- (void)selectionChanged:(NSButton *)sender { NSUInteger count = 0; for (NSButton *check in self.checks) if (check.state == NSControlStateValueOn) count++; self.validation.stringValue = [NSString stringWithFormat:@"已选择 %lu 个文件", (unsigned long)count]; self.validation.textColor = Muted(); if (sender) [self showPreview:sender]; }
- (void)showPreview:(NSButton *)sender {
    NSUInteger generation = ++self.previewGeneration; self.preview.string = @"正在读取变更…";
    __weak typeof(self) weakSelf = self;
    if (self.readPreview) self.readPreview(self.changes[sender.tag][@"path"], ^(NSString *text) { if (weakSelf && generation == weakSelf.previewGeneration) weakSelf.preview.string = text ?: @"无法读取预览。"; });
}
- (void)cancel:(id)sender { self.previewGeneration++; [self.window.sheetParent endSheet:self.window]; [self.window orderOut:nil]; }
- (void)save:(id)sender {
    NSMutableArray *paths = NSMutableArray.array; for (NSUInteger i = 0; i < self.checks.count; i++) if (self.checks[i].enabled && self.checks[i].state == NSControlStateValueOn) [paths addObject:self.changes[i][@"path"]];
    NSString *message = [self.message.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!paths.count || !message.length) { self.validation.stringValue = @"请至少选择一个文件，并填写提交说明。"; self.validation.textColor = NSColor.systemRedColor; return; }
    [self cancel:nil]; if (self.submit) self.submit(paths.copy, message);
}
@end
