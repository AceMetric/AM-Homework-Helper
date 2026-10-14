// System list selection, keyboard handling and geometry; no painted selection chrome.
@interface AMNativeSidebar () <NSOutlineViewDataSource,NSOutlineViewDelegate>
@property(readwrite) NSOutlineView *outline;
@property(readwrite) NSScrollView *scroll;
@property NSArray *items;
@property BOOL updating;
@property NSButton *account;
@property NSTextField *footer;
@end
@implementation AMNativeSidebar
- (void)loadView {
    Surface *root=Box(nil,0);self.view=root;
    NSTextField *brand=Text(@"AM Helper",14,NSFontWeightSemibold,Ink());brand.accessibilityLabel=@"AM's Homework Helper";
    self.scroll=NSScrollView.new;self.scroll.hasVerticalScroller=YES;self.scroll.autohidesScrollers=YES;self.scroll.drawsBackground=NO;
    self.outline=NSOutlineView.new;self.outline.style=NSTableViewStyleSourceList;self.outline.headerView=nil;self.outline.rowHeight=30;self.outline.intercellSpacing=NSMakeSize(0,2);self.outline.backgroundColor=NSColor.clearColor;
    NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"navigation"];column.resizingMask=NSTableColumnAutoresizingMask;[self.outline addTableColumn:column];self.outline.outlineTableColumn=column;self.outline.dataSource=self;self.outline.delegate=self;self.outline.accessibilityLabel=@"页面与课程导航";self.scroll.documentView=self.outline;
    NSStackView *bottom=NSStackView.new;bottom.orientation=NSUserInterfaceLayoutOrientationVertical;bottom.alignment=NSLayoutAttributeLeading;bottom.spacing=6;
    for(NSArray *entry in @[@[@"开始使用",@"help",@"questionmark.circle"],@[@"连接 GitHub",@"account",@"person.crop.circle"],@[@"设置",@"settings",@"gearshape"]]){
        NSButton *button=[NSButton buttonWithTitle:entry[0] target:self action:@selector(footerAction:)];button.identifier=entry[1];button.image=[NSImage imageWithSystemSymbolName:entry[2] accessibilityDescription:nil];button.imagePosition=NSImageLeft;button.alignment=NSTextAlignmentLeft;button.bordered=NO;button.font=[NSFont systemFontOfSize:13];button.accessibilityLabel=entry[0];[bottom addArrangedSubview:button];if([entry[1] isEqual:@"account"])self.account=button;
    }
    self.footer=Text(@"",10,NSFontWeightRegular,Muted());[bottom addArrangedSubview:self.footer];
    for(NSView *child in @[brand,self.scroll,bottom]){child.translatesAutoresizingMaskIntoConstraints=NO;[root addSubview:child];}
    [NSLayoutConstraint activateConstraints:@[[brand.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:16],[brand.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor constant:16],[brand.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-12],[self.scroll.topAnchor constraintEqualToAnchor:brand.bottomAnchor constant:20],[self.scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[self.scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],[self.scroll.bottomAnchor constraintEqualToAnchor:bottom.topAnchor constant:-12],[bottom.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:16],[bottom.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-12],[bottom.bottomAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.bottomAnchor constant:-12]]];
}
- (void)updateItems:(NSArray *)items selected:(NSString *)identifier account:(NSString *)account footer:(NSString *)footer {
    (void)self.view;NSPoint offset=self.scroll.contentView.bounds.origin;BOOL expanded=YES;id group=self.items.lastObject;if(group)expanded=[self.outline isItemExpanded:group];
    self.updating=YES;
    if(![self.items isEqual:items]){self.items=[[NSArray alloc] initWithArray:items copyItems:YES];[self.outline reloadData];if(expanded && self.items.count)[self.outline expandItem:self.items.lastObject];}
    NSInteger selected=-1;for(NSInteger row=0;row<self.outline.numberOfRows;row++)if([[[self.outline itemAtRow:row] objectForKey:@"id"] isEqual:identifier]){selected=row;break;}
    [self.outline selectRowIndexes:selected>=0 ? [NSIndexSet indexSetWithIndex:selected]:NSIndexSet.indexSet byExtendingSelection:NO];self.updating=NO;
    self.account.title=account ?: @"连接 GitHub";self.account.toolTip=self.account.title;self.account.accessibilityLabel=self.account.title;self.footer.stringValue=footer ?: @"";
    [self.scroll.contentView scrollToPoint:offset];[self.scroll reflectScrolledClipView:self.scroll.contentView];
}
- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item {return item ? [item[@"children"] count]:self.items.count;}
- (id)outlineView:(NSOutlineView *)outline child:(NSInteger)index ofItem:(id)item {return item ? item[@"children"][index]:self.items[index];}
- (BOOL)outlineView:(NSOutlineView *)outline isItemExpandable:(id)item {return item[@"children"]!=nil;}
- (BOOL)outlineView:(NSOutlineView *)outline isGroupItem:(id)item {return item[@"children"]!=nil;}
- (BOOL)outlineView:(NSOutlineView *)outline shouldSelectItem:(id)item {return item[@"children"]==nil;}
- (NSView *)outlineView:(NSOutlineView *)outline viewForTableColumn:(NSTableColumn *)column item:(id)item {
    NSTableCellView *cell=[outline makeViewWithIdentifier:@"native-navigation-cell" owner:self];
    if(!cell){cell=NSTableCellView.new;cell.identifier=@"native-navigation-cell";NSImageView *image=NSImageView.new;NSTextField *label=Text(@"",13,NSFontWeightRegular,Ink());NSTextField *count=Text(@"",11,NSFontWeightRegular,Muted());count.identifier=@"pending-count";count.alignment=NSTextAlignmentRight;cell.imageView=image;cell.textField=label;
        for(NSView *child in @[image,label,count]){child.translatesAutoresizingMaskIntoConstraints=NO;[cell addSubview:child];}
        [NSLayoutConstraint activateConstraints:@[[image.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],[image.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],[image.widthAnchor constraintEqualToConstant:16],[image.heightAnchor constraintEqualToConstant:16],[label.leadingAnchor constraintEqualToAnchor:image.trailingAnchor constant:8],[label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],[label.trailingAnchor constraintLessThanOrEqualToAnchor:count.leadingAnchor constant:-4],[count.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],[count.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],[count.widthAnchor constraintEqualToConstant:30]]];
    }
    cell.textField.stringValue=item[@"label"] ?: @"";cell.imageView.image=[NSImage imageWithSystemSymbolName:item[@"symbol"] ?: @"books.vertical" accessibilityDescription:nil];cell.imageView.hidden=item[@"children"]!=nil;cell.toolTip=item[@"status"] ?: item[@"label"];cell.accessibilityLabel=cell.textField.stringValue;
    for(NSView *child in cell.subviews)if([child.identifier isEqual:@"pending-count"])[(NSTextField *)child setStringValue:[item[@"pending"] integerValue]>0 ? [item[@"pending"] description]:@""];
    return cell;
}
- (void)outlineViewSelectionDidChange:(NSNotification *)notification {if(self.updating)return;NSInteger row=self.outline.selectedRow;if(row<0)return;NSString *identifier=[[self.outline itemAtRow:row] objectForKey:@"id"];if(identifier && self.actionHandler)self.actionHandler(identifier);}
- (void)footerAction:(NSButton *)sender {if(self.actionHandler)self.actionHandler(sender.identifier);}
@end

@interface AMTaskTable:NSTableView
@property(copy) void (^closeSelection)(void);
@end
@implementation AMTaskTable
- (void)keyDown:(NSEvent *)event {if([event.charactersIgnoringModifiers isEqual:@"\033"] && self.closeSelection){self.closeSelection();return;}[super keyDown:event];}
@end
@interface AMNativeTaskList () <NSTableViewDataSource,NSTableViewDelegate>
@property(readwrite) NSTableView *table;
@property(readwrite) NSScrollView *scroll;
@property NSTextField *heading;
@property NSTextField *empty;
@property NSArray *tasks;
@property BOOL updating;
@end
@implementation AMNativeTaskList
- (void)loadView {
    Surface *root=Box(Canvas(),0);self.view=root;self.heading=Text(@"",12,NSFontWeightMedium,Muted());self.scroll=NSScrollView.new;self.scroll.hasVerticalScroller=YES;self.scroll.autohidesScrollers=YES;self.scroll.drawsBackground=NO;
    AMTaskTable *table=AMTaskTable.new;self.table=table;table.style=NSTableViewStyleInset;table.headerView=nil;table.rowHeight=52;table.intercellSpacing=NSMakeSize(0,1);table.columnAutoresizingStyle=NSTableViewUniformColumnAutoresizingStyle;table.allowsEmptySelection=YES;table.backgroundColor=Canvas();
    NSTableColumn *check=[[NSTableColumn alloc] initWithIdentifier:@"check"];check.width=32;check.minWidth=32;check.maxWidth=32;[table addTableColumn:check];NSTableColumn *title=[[NSTableColumn alloc] initWithIdentifier:@"title"];title.width=400;title.minWidth=160;title.resizingMask=NSTableColumnAutoresizingMask;[table addTableColumn:title];NSTableColumn *date=[[NSTableColumn alloc] initWithIdentifier:@"date"];date.width=148;date.minWidth=148;date.maxWidth=148;[table addTableColumn:date];NSTableColumn *action=[[NSTableColumn alloc] initWithIdentifier:@"actions"];action.width=60;action.minWidth=60;action.maxWidth=60;[table addTableColumn:action];
    table.dataSource=self;table.delegate=self;table.target=self;table.doubleAction=@selector(editSelected:);table.accessibilityLabel=@"任务列表";self.scroll.documentView=table;
    self.empty=Text(@"暂无匹配任务，可调整筛选或点＋快速录入。",13,NSFontWeightRegular,Muted());self.empty.alignment=NSTextAlignmentCenter;
    for(NSView *child in @[self.heading,self.scroll,self.empty]){child.translatesAutoresizingMaskIntoConstraints=NO;[root addSubview:child];}
    [NSLayoutConstraint activateConstraints:@[[self.heading.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:8],[self.heading.topAnchor constraintEqualToAnchor:root.topAnchor],[self.heading.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-8],[self.scroll.topAnchor constraintEqualToAnchor:self.heading.bottomAnchor constant:12],[self.scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[self.scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],[self.scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],[self.empty.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],[self.empty.topAnchor constraintEqualToAnchor:self.scroll.topAnchor constant:64],[self.empty.widthAnchor constraintLessThanOrEqualToAnchor:root.widthAnchor constant:-24]]];
    __weak typeof(self) owner=self;table.closeSelection=^{if(owner.actionHandler)owner.actionHandler(@"close",@"");};root.onResize=^{CGFloat width=owner.scroll.contentSize.width;owner.table.tableColumns[1].width=MAX(160,width-264);};
}
- (void)updateGroups:(NSArray *)groups selected:(NSString *)identifier heading:(NSString *)heading {
    NSMutableArray *rows=NSMutableArray.array;for(NSDictionary *group in groups){NSArray *tasks=group[@"tasks"];if(!tasks.count)continue;[rows addObject:@{@"group":@YES,@"title":[NSString stringWithFormat:@"%@ · %lu",group[@"title"],(unsigned long)tasks.count],@"id":[@"group:" stringByAppendingString:group[@"title"]]}];[rows addObjectsFromArray:tasks];}[self updateTasks:rows selected:identifier heading:heading];
}
- (void)updateTasks:(NSArray *)tasks selected:(NSString *)identifier heading:(NSString *)heading {
    (void)self.view;NSPoint offset=self.scroll.contentView.bounds.origin;self.updating=YES;
    if(![self.tasks isEqual:tasks]){self.tasks=[[NSArray alloc] initWithArray:tasks copyItems:YES];[self.table reloadData];}
    NSInteger row=-1;for(NSUInteger index=0;index<self.tasks.count;index++)if([self.tasks[index][@"id"] isEqual:identifier]){row=(NSInteger)index;break;}
    [self.table selectRowIndexes:row>=0 ? [NSIndexSet indexSetWithIndex:row]:NSIndexSet.indexSet byExtendingSelection:NO];self.updating=NO;self.heading.stringValue=heading ?: @"";self.empty.hidden=self.tasks.count>0;[self.scroll.contentView scrollToPoint:offset];[self.scroll reflectScrolledClipView:self.scroll.contentView];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table{return self.tasks.count;}
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSDictionary *task=self.tasks[row];if([task[@"group"] boolValue])return Text(task[@"title"],12,NSFontWeightSemibold,Muted());NSString *identifier=column.identifier;
    if([identifier isEqual:@"check"]){NSButton *button=[NSButton checkboxWithTitle:@"" target:self action:@selector(toggle:)];button.identifier=task[@"id"];button.state=[task[@"completed"] boolValue] ? NSControlStateValueOn:NSControlStateValueOff;button.enabled=![task[@"deleted"] boolValue];button.accessibilityLabel=[NSString stringWithFormat:@"切换完成状态：%@",task[@"title"]];return button;}
    if([identifier isEqual:@"actions"]){NSButton *button=[NSButton buttonWithTitle:@"" image:[NSImage imageWithSystemSymbolName:@"ellipsis" accessibilityDescription:@"任务操作"] target:self action:@selector(more:)];button.identifier=task[@"id"];button.bordered=NO;button.accessibilityLabel=[@"任务操作：" stringByAppendingString:task[@"title"]];return button;}
    NSTableCellView *cell=[table makeViewWithIdentifier:identifier owner:self];
    if(!cell){cell=NSTableCellView.new;cell.identifier=identifier;NSTextField *title=Text(@"",13,NSFontWeightMedium,Ink());NSTextField *subtitle=Text(@"",11,NSFontWeightRegular,Muted());subtitle.identifier=@"subtitle";cell.textField=title;for(NSView *child in @[title,subtitle]){child.translatesAutoresizingMaskIntoConstraints=NO;[cell addSubview:child];}[NSLayoutConstraint activateConstraints:@[[title.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],[title.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],[title.topAnchor constraintEqualToAnchor:cell.topAnchor constant:8],[subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],[subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4]]];}
    NSString *subtitle=@"";if([identifier isEqual:@"title"]){cell.textField.stringValue=task[@"title"] ?: @"";subtitle=task[@"subject"] ?: @"";if([task[@"priority"] integerValue]>0)subtitle=[NSString stringWithFormat:@"%@%@%@",subtitle,subtitle.length ? @" · ":@"",[task[@"priority"] integerValue]==2 ? @"紧急":@"重要"];}else {NSDateFormatter *formatter=NSDateFormatter.new;formatter.dateFormat=@"M月d日 HH:mm";cell.textField.stringValue=[task[@"due"] isKindOfClass:NSDate.class] ? [formatter stringFromDate:task[@"due"]]:@"未填写截止时间";subtitle=task[@"displayStatus"] ?: @"";}
    cell.toolTip=cell.textField.stringValue;for(NSView *child in cell.subviews)if([child.identifier isEqual:@"subtitle"])[(NSTextField *)child setStringValue:subtitle];return cell;
}
- (BOOL)tableView:(NSTableView *)table isGroupRow:(NSInteger)row{return [self.tasks[row][@"group"] boolValue];}
- (BOOL)tableView:(NSTableView *)table shouldSelectRow:(NSInteger)row{return ![self.tasks[row][@"group"] boolValue];}
- (CGFloat)tableView:(NSTableView *)table heightOfRow:(NSInteger)row{return [self.tasks[row][@"group"] boolValue] ? 32:52;}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {if(self.updating)return;NSInteger row=self.table.selectedRow;if(row>=0 && ![self.tasks[row][@"group"] boolValue] && self.actionHandler)self.actionHandler(@"select",self.tasks[row][@"id"]);}
- (void)toggle:(NSButton *)sender {if(self.actionHandler)self.actionHandler(@"toggle",sender.identifier);}
- (void)more:(NSButton *)sender {NSMenu *menu=self.menuProvider ? self.menuProvider(sender.identifier):nil;if(menu)[menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,NSHeight(sender.bounds)) inView:sender];}
- (void)editSelected:(id)sender {NSInteger row=self.table.clickedRow>=0 ? self.table.clickedRow:self.table.selectedRow;if(row>=0 && ![self.tasks[row][@"group"] boolValue] && self.actionHandler)self.actionHandler(@"edit",self.tasks[row][@"id"]);}
- (void)focusSelection {[self.view.window makeFirstResponder:self.table];if(self.table.selectedRow>=0)[self.table scrollRowToVisible:self.table.selectedRow];}
@end

// Native form controls retain intrinsic heights; only the scroll document grows.
@interface AMFormScroll:NSScrollView
@property NSStackView *form;
@property BOOL layingOutForm;
@end
@implementation AMFormScroll
- (void)layout {
    [super layout];if(self.layingOutForm || !self.form)return;self.layingOutForm=YES;
    NSView *document=self.documentView;CGFloat width=MAX(1,self.contentSize.width);document.frame=NSMakeRect(0,0,width,MAX(self.contentSize.height,NSHeight(document.frame)));
    [document layoutSubtreeIfNeeded];CGFloat height=MAX(self.contentSize.height,self.form.fittingSize.height);document.frame=NSMakeRect(0,0,width,height);self.layingOutForm=NO;
}
@end
NSScrollView *AMScrollableForm(NSStackView *stack){
    AMFormScroll *scroll=AMFormScroll.new;scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;scroll.drawsBackground=NO;Surface *document=Box(nil,0);document.frame=NSMakeRect(0,0,640,640);scroll.documentView=document;scroll.form=stack;stack.translatesAutoresizingMaskIntoConstraints=NO;[document addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:document.topAnchor]]];return scroll;
}
