@interface AMTaskTimeController : NSWindowController <NSTableViewDataSource,NSTableViewDelegate,NSWindowDelegate>
@property NSDictionary *task;
@property NSArray *entries;
@property NSArray *undoEntries;
@property NSArray *undoExpected;
@property NSTableView *table;
@property NSTextField *summary;
@property NSButton *toggle;
@property NSTimer *timer;
@end
@implementation AMTaskTimeController
- (instancetype)initWithTask:(NSDictionary *)task {
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,580,400) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    if(!(self=[super initWithWindow:window]))return nil;self.task=task;window.title=[@"实际用时 · " stringByAppendingString:task[@"title"] ?: @""];window.contentMinSize=NSMakeSize(480,280);window.releasedWhenClosed=NO;window.delegate=self;
    Surface *root=Box(Canvas(),0);window.contentView=root;
    self.summary=Text(@"",14,NSFontWeightMedium,Ink());self.toggle=Button(@"开始",self,@selector(toggleTimer:),1);
    NSStackView *actions=[NSStackView stackViewWithViews:@[self.toggle,Button(@"结束",self,@selector(finishTimer:),0),Button(@"补录…",self,@selector(addEntry:),0),Button(@"修改…",self,@selector(editEntry:),0),Button(@"删除",self,@selector(deleteEntry:),0),Button(@"撤销",self,@selector(undoEntry:),0)]];actions.spacing=8;
    self.table=NSTableView.new;self.table.delegate=self;self.table.dataSource=self;self.table.rowHeight=30;NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"time"];column.title=@"记录";[self.table addTableColumn:column];
    NSScrollView *scroll=NSScrollView.new;scroll.documentView=self.table;scroll.hasVerticalScroller=YES;
    for(NSView *view in @[self.summary,actions,scroll]){[root addSubview:view];view.translatesAutoresizingMaskIntoConstraints=NO;}
    [NSLayoutConstraint activateConstraints:@[[self.summary.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:16],[self.summary.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16],[self.summary.topAnchor constraintEqualToAnchor:root.topAnchor constant:16],[actions.leadingAnchor constraintEqualToAnchor:self.summary.leadingAnchor],[actions.topAnchor constraintEqualToAnchor:self.summary.bottomAnchor constant:12],[actions.trailingAnchor constraintLessThanOrEqualToAnchor:self.summary.trailingAnchor],[scroll.topAnchor constraintEqualToAnchor:actions.bottomAnchor constant:12],[scroll.leadingAnchor constraintEqualToAnchor:self.summary.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.summary.trailingAnchor],[scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-16]]];
    __weak typeof(self) weak=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[weak refresh];}];[self refresh];return self;
}
- (void)windowWillClose:(NSNotification *)note {[self.timer invalidate];}
- (void)refresh {NSError *error=nil;NSArray *all=AMTimeEntries(&error);NSMutableArray *rows=NSMutableArray.array;for(NSDictionary *entry in all)if([entry[@"taskID"] isEqual:self.task[@"id"]])[rows addObject:entry];self.entries=rows;NSInteger seconds=(NSInteger)[AMTimeTracker.shared secondsForTask:self.task[@"id"]];self.summary.stringValue=error.localizedDescription ?: AMTimeTracker.shared.lastError.localizedDescription ?: [NSString stringWithFormat:@"累计 %ld 小时 %ld 分 %ld 秒%@",(long)(seconds/3600),(long)(seconds/60%60),(long)(seconds%60),AMTimeTracker.shared.running && [AMTimeTracker.shared.taskID isEqual:self.task[@"id"]] ? @" · 计时中":@""];self.toggle.title=[AMTimeTracker.shared.taskID isEqual:self.task[@"id"]] ? (AMTimeTracker.shared.running ? @"暂停":@"重试保存"):@"开始";self.toggle.enabled=![self.task[@"completed"] boolValue] && ![self.task[@"deleted"] boolValue];NSInteger selected=self.table.selectedRow;[self.table reloadData];if(selected>=0 && selected<(NSInteger)rows.count)[self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:selected] byExtendingSelection:NO];}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table{return self.entries.count;}
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {NSDictionary *entry=self.entries[row];return [NSString stringWithFormat:@"%@ · %.1f 分钟 · %@",DDLFormatDate(entry[@"date"],@"M月d日 HH:mm"),[entry[@"seconds"] doubleValue]/60,[entry[@"manual"] boolValue] ? @"补录":@"计时"];}
- (void)showError:(NSError *)error {if(error){NSAlert *alert=NSAlert.new;alert.messageText=error.localizedDescription;[alert runModal];}}
- (void)toggleTimer:(id)sender {NSError *error=nil;if([AMTimeTracker.shared.taskID isEqual:self.task[@"id"]])[AMTimeTracker.shared pause:&error];else [AMTimeTracker.shared startTask:self.task[@"id"] error:&error];[self showError:error];[self refresh];}
// 结束会先保存当前计时，再关闭详情；关闭窗口本身不隐式停止计时。
- (void)finishTimer:(id)sender {NSError *error=nil;if([AMTimeTracker.shared.taskID isEqual:self.task[@"id"]] && ![AMTimeTracker.shared pause:&error]){[self showError:error];return;}[self close];}
- (void)saveEntries:(NSArray *)next {NSError *error=nil;NSArray *old=AMTimeEntries(&error);if(old && AMSaveTimeEntries(next,&error)){self.undoEntries=old;self.undoExpected=next;}[self showError:error];[self refresh];}
- (void)changeEntry:(NSDictionary *)entry {
    NSError *error=nil;if(![AMTimeTracker.shared pause:&error]){[self showError:error];return;}
    NSAlert *alert=NSAlert.new;alert.messageText=entry ? @"修改用时":@"补录用时";NSStackView *fields=NSStackView.new;fields.orientation=NSUserInterfaceLayoutOrientationVertical;NSDatePicker *date=NSDatePicker.new;date.datePickerElements=NSDatePickerElementFlagYearMonthDay|NSDatePickerElementFlagHourMinute;date.dateValue=entry[@"date"] ?: NSDate.date;NSTextField *minutes=[NSTextField textFieldWithString:entry ? [NSString stringWithFormat:@"%.2f",[entry[@"seconds"] doubleValue]/60]:@""];minutes.placeholderString=@"分钟";[fields addArrangedSubview:date];[fields addArrangedSubview:minutes];fields.frame=NSMakeRect(0,0,300,72);[minutes.widthAnchor constraintEqualToConstant:300].active=YES;alert.accessoryView=fields;[alert addButtonWithTitle:@"保存"];[alert addButtonWithTitle:@"取消"];if([alert runModal]!=NSAlertFirstButtonReturn)return;
    NSScanner *scanner=[NSScanner scannerWithString:minutes.stringValue];double value=0;if(![scanner scanDouble:&value] || !scanner.isAtEnd || !isfinite(value) || value<=0 || value>527040){[self showError:[NSError errorWithDomain:@"AMTaskTime" code:3 userInfo:@{NSLocalizedDescriptionKey:@"请输入有效分钟数"}]];return;}
    NSMutableArray *rows=[AMTimeEntries(&error) mutableCopy];if(!rows){[self showError:error];return;}if(entry)[rows removeObject:entry];[rows addObject:@{@"id":entry[@"id"] ?: NSUUID.UUID.UUIDString,@"taskID":self.task[@"id"],@"date":date.dateValue,@"seconds":@(value*60),@"manual":@YES}];[self saveEntries:rows];
}
- (void)addEntry:(id)sender {[self changeEntry:nil];}
- (void)editEntry:(id)sender {if(self.table.selectedRow>=0)[self changeEntry:self.entries[self.table.selectedRow]];}
- (void)deleteEntry:(id)sender {if(self.table.selectedRow<0)return;NSError *error=nil;if(![AMTimeTracker.shared pause:&error]){[self showError:error];return;}NSMutableArray *rows=[AMTimeEntries(&error) mutableCopy];if(rows){[rows removeObject:self.entries[self.table.selectedRow]];[self saveEntries:rows];}else [self showError:error];}
- (void)undoEntry:(id)sender {
    // 只撤销本次编辑涉及的记录，保留之后新增的其他任务用时；冲突时不覆盖新数据。
    if(!self.undoEntries)return;NSError *error=nil;if(![AMTimeTracker.shared pause:&error]){[self showError:error];return;}NSArray *current=AMTimeEntries(&error);if(!current){[self showError:error];return;}
    NSMutableDictionary *before=NSMutableDictionary.dictionary,*after=NSMutableDictionary.dictionary,*now=NSMutableDictionary.dictionary;for(NSDictionary *entry in self.undoEntries)before[entry[@"id"]]=entry;for(NSDictionary *entry in self.undoExpected)after[entry[@"id"]]=entry;for(NSDictionary *entry in current)now[entry[@"id"]]=entry;NSMutableSet *changed=[NSMutableSet setWithArray:before.allKeys];[changed addObjectsFromArray:after.allKeys];
    for(NSString *key in changed){if([before[key] isEqual:after[key]])continue;if(![(now[key] ?: NSNull.null) isEqual:after[key] ?: NSNull.null]){[self showError:[NSError errorWithDomain:@"AMTaskTime" code:4 userInfo:@{NSLocalizedDescriptionKey:@"该记录已有新修改，未覆盖；请重新核对用时"}]];return;}}
    for(NSString *key in changed)if(![before[key] isEqual:after[key]]){if(before[key])now[key]=before[key];else [now removeObjectForKey:key];}[self saveEntries:now.allValues];
}
@end
void AMShowTaskTime(NSDictionary *task,NSWindow *parent){static AMTaskTimeController *controller;if(controller.window.visible && [controller.task[@"id"] isEqual:task[@"id"]]){[controller.window makeKeyAndOrderFront:nil];return;}[controller close];controller=[[AMTaskTimeController alloc] initWithTask:task];[controller.window center];[controller showWindow:nil];}
