// Native review UI; the report never starts Git operations by itself.
static NSTextView *PFText(NSView *root,NSRect frame,BOOL editable){
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:frame];scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;scroll.borderType=NSBezelBorder;scroll.drawsBackground=YES;scroll.backgroundColor=Card();
    NSTextView *text=[[PastelNotesView alloc] initWithFrame:NSMakeRect(0,0,frame.size.width-16,frame.size.height)];text.editable=editable;text.richText=NO;text.font=[NSFont systemFontOfSize:13];text.textColor=Ink();text.backgroundColor=Card();text.textContainerInset=NSMakeSize(8,8);text.autoresizingMask=NSViewWidthSizable;text.textContainer.widthTracksTextView=YES;scroll.documentView=text;[root addSubview:scroll];return text;
}
@interface PFImageView:NSView
@property NSImage *image;
@property NSArray *region;
@end
@implementation PFImageView
- (void)drawRect:(NSRect)dirty {
    [Card() setFill];NSRectFill(self.bounds);if(!self.image)return;
    NSSize size=self.image.size;CGFloat ratio=MIN(self.bounds.size.width/MAX(1,size.width),self.bounds.size.height/MAX(1,size.height));NSRect r=NSMakeRect((self.bounds.size.width-size.width*ratio)/2,(self.bounds.size.height-size.height*ratio)/2,size.width*ratio,size.height*ratio);
    [self.image drawInRect:r];if(self.region.count==4){NSRect highlight=NSMakeRect(r.origin.x+[self.region[0] doubleValue]*r.size.width,r.origin.y+(1-[self.region[1] doubleValue]-[self.region[3] doubleValue])*r.size.height,[self.region[2] doubleValue]*r.size.width,[self.region[3] doubleValue]*r.size.height);[NSColor.systemOrangeColor setStroke];NSBezierPath *path=[NSBezierPath bezierPathWithRect:highlight];path.lineWidth=3;[path stroke];}
}
@end
// A real resizable reader instead of a concatenated NSAlert accessory.
@interface PFMaterials:NSWindowController<NSTableViewDataSource,NSTableViewDelegate,NSOutlineViewDataSource,NSOutlineViewDelegate,NSWindowDelegate>
@property NSMutableArray *rows;
@property NSMutableArray *treeRoots;
@property NSMutableSet *excluded;
@property NSDictionary *snapshot;
@property NSString *requirements;
@property NSTableView *table;
@property NSTextView *text;
@property NSScrollView *imageScroll;
@property PFImageView *image;
@property NSButton *include;
@property NSTextField *heading;
@property NSTextField *summary;
@property NSPopUpButton *destination;
@property CGFloat zoom;
@property BOOL fit;
- (instancetype)initWithSnapshot:(NSDictionary *)snapshot report:(NSDictionary *)report requirements:(NSString *)requirements;
- (NSArray *)selectedImages;
- (NSDictionary *)selectedSnapshot;
- (void)layout;
- (void)rebuildTree:(NSString *)selectedPath;
- (NSDictionary *)selectedNode;
- (NSInteger)selectedIndex;
@end
@implementation PFMaterials
- (instancetype)initWithSnapshot:(NSDictionary *)snapshot report:(NSDictionary *)report requirements:(NSString *)requirements {
    DDLFormPanel *panel=[[DDLFormPanel alloc] initWithContentRect:NSMakeRect(0,0,1040,720) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    if((self=[super initWithWindow:panel])){
        panel.delegate=self;panel.title=@"预览交给助手的材料";panel.minSize=NSMakeSize(820,580);panel.releasedWhenClosed=NO;self.snapshot=snapshot;self.requirements=requirements;self.excluded=NSMutableSet.set;self.fit=YES;self.zoom=1;
        self.rows=NSMutableArray.array;if(requirements.length)[self.rows addObject:@{@"path":@"题目与评分要求",@"requirements":@YES}];
        NSMutableArray *documents=NSMutableArray.array;for(NSString *path in snapshot[@"paths"])if(snapshot[@"files"][path][@"text"])[documents addObject:@{@"path":path}];
        [documents sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){BOOL am=[@[@"md",@"markdown",@"mdx"] containsObject:[a[@"path"] pathExtension].lowercaseString],bm=[@[@"md",@"markdown",@"mdx"] containsObject:[b[@"path"] pathExtension].lowercaseString];return am!=bm ? (am ? NSOrderedAscending:NSOrderedDescending):[a[@"path"] localizedStandardCompare:b[@"path"]];}];
        [self.rows addObjectsFromArray:documents];for(NSDictionary *row in report[@"images"]){NSMutableDictionary *image=row.mutableCopy;image[@"image"]=@YES;[self.rows addObject:image];}
        Surface *root=Box(Canvas(),0);root.frame=NSMakeRect(0,0,1040,720);root.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;panel.contentView=root;
        Put(root,Text(@"确认交给助手的文件",20,NSFontWeightSemibold,Ink()),20,16,900,30);
        Put(root,Text(@"仅使用已勾选材料，不会自动发送或提交。",13,NSFontWeightRegular,Muted()),20,54,980,24);
        self.summary=Text(@"",12,NSFontWeightRegular,Muted());Put(root,self.summary,20,84,980,24);
        NSScrollView *list=[[NSScrollView alloc] initWithFrame:NSMakeRect(20,120,270,474)];list.hasVerticalScroller=YES;list.autohidesScrollers=YES;self.table=NSOutlineView.new;NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"material"];column.width=250;[self.table addTableColumn:column];[(NSOutlineView *)self.table setOutlineTableColumn:column];self.table.headerView=nil;self.table.rowHeight=46;self.table.dataSource=self;self.table.delegate=self;self.table.accessibilityLabel=@"交给助手的文件清单";list.documentView=self.table;[root addSubview:list];
        self.heading=Text(@"",13,NSFontWeightSemibold,Ink());Put(root,self.heading,308,120,700,24);
        self.include=[NSButton checkboxWithTitle:@"包含此文件" target:self action:@selector(toggle:)];Put(root,self.include,308,152,124,28);
        for(NSArray *spec in @[@[@"适合",@0],@[@"100%",@1],@[@"＋",@2],@[@"−",@3],@[@"前移",@4],@[@"后移",@5]]){NSInteger tag=[spec[1] integerValue];NSButton *b=Button(spec[0],self,@selector(tool:),0);b.tag=tag;b.identifier=[NSString stringWithFormat:@"material-tool-%ld",(long)tag];Put(root,b,450+tag*88,152,80,28);}
        self.text=PFText(root,NSMakeRect(308,192,712,402),NO);self.text.font=[NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];self.text.accessibilityLabel=@"材料全文与行号";
        self.imageScroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(308,192,712,402)];self.imageScroll.hasVerticalScroller=YES;self.imageScroll.hasHorizontalScroller=YES;self.imageScroll.autohidesScrollers=YES;self.image=[[PFImageView alloc] initWithFrame:NSMakeRect(0,0,712,402)];self.imageScroll.documentView=self.image;[root addSubview:self.imageScroll];
        self.destination=NSPopUpButton.new;[self.destination addItemsWithTitles:@[@"网页／聊天助手：上传附件",@"本机助手：读取文件并自动接回"]];Put(root,self.destination,20,620,360,30);
        NSButton *cancel=Button(@"取消",self,@selector(cancel:),0);cancel.identifier=@"material-cancel";cancel.keyEquivalent=@"\033";cancel.keyEquivalentModifierMask=0;Put(root,cancel,796,656,88,32);
        NSButton *prepare=Button(@"准备材料",self,@selector(prepare:),1);prepare.identifier=@"material-prepare";Put(root,prepare,900,656,120,32);panel.defaultButtonCell=prepare.cell;
        __weak typeof(self) owner=self;panel.onCancel=^{[owner cancel:nil];};panel.onConfirm=^{[owner prepare:nil];};root.onResize=^{[owner layout];};[self rebuildTree:nil];if(self.table.numberOfRows)[self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];[self layout];
    }return self;
}
- (void)layout {
    CGFloat w=NSWidth(self.window.contentView.bounds),h=NSHeight(self.window.contentView.bounds),x=MIN(290,w*.28)+18,body=h-246;NSView *root=self.window.contentView;
    self.table.enclosingScrollView.frame=NSMakeRect(20,120,x-38,body);self.table.tableColumns.firstObject.width=x-58;
    self.heading.frame=NSMakeRect(x,120,w-x-20,24);self.include.frame=NSMakeRect(x,152,120,28);
    for(NSView *v in root.subviews){if([v.identifier hasPrefix:@"material-tool-"]){NSInteger tag=[v.identifier substringFromIndex:14].integerValue;v.frame=NSMakeRect(x+128+tag*MAX(55,(w-x-148)/6),152,MAX(50,(w-x-148)/6-4),28);}else if([v.identifier isEqual:@"material-cancel"])v.frame=NSMakeRect(w-244,h-64,88,32);else if([v.identifier isEqual:@"material-prepare"])v.frame=NSMakeRect(w-140,h-64,120,32);}
    self.text.enclosingScrollView.frame=self.imageScroll.frame=NSMakeRect(x,192,w-x-20,MAX(100,body-72));self.destination.frame=NSMakeRect(20,h-106,MIN(430,w-40),30);[self sizeImage];
}
- (void)sizeImage {if(!self.image.image)return;NSSize size=self.image.image.size,viewport=self.imageScroll.contentSize;CGFloat scale=self.fit ? MIN(viewport.width/MAX(1,size.width),viewport.height/MAX(1,size.height)):self.zoom;self.image.frame=NSMakeRect(0,0,MAX(viewport.width,size.width*scale),MAX(viewport.height,size.height*scale));self.image.needsDisplay=YES;}
- (NSDictionary *)selectedNode {NSInteger index=self.table.selectedRow;return index>=0 ? [(NSOutlineView *)self.table itemAtRow:index]:nil;}
- (NSInteger)selectedIndex {NSDictionary *row=[self selectedNode][@"material"];NSUInteger index=row ? [self.rows indexOfObjectIdenticalTo:row]:NSNotFound;return index==NSNotFound ? -1:(NSInteger)index;}
- (void)rebuildTree:(NSString *)selectedPath {
    NSOutlineView *outline=(NSOutlineView *)self.table;NSMutableSet *expanded=NSMutableSet.set;BOOL first=self.treeRoots==nil;
    for(NSInteger i=0;i<outline.numberOfRows;i++){NSDictionary *node=[outline itemAtRow:i];if(node[@"children"] && [outline isItemExpanded:node])[expanded addObject:node[@"path"]];}
    self.treeRoots=NSMutableArray.array;NSMutableDictionary *folders=NSMutableDictionary.dictionary,*leaves=NSMutableDictionary.dictionary;
    for(NSDictionary *row in self.rows){NSString *path=row[@"path"];NSMutableArray *children=self.treeRoots;NSArray *parts=path.pathComponents;NSString *prefix=@"";
        for(NSUInteger i=0;i+1<parts.count;i++){prefix=prefix.length ? [prefix stringByAppendingPathComponent:parts[i]]:parts[i];NSMutableDictionary *node=folders[prefix];if(!node){node=[@{@"path":prefix,@"children":NSMutableArray.array} mutableCopy];folders[prefix]=node;[children addObject:node];}children=node[@"children"];}
        NSDictionary *leaf=@{@"path":path,@"material":row};[children addObject:leaf];leaves[path]=leaf;
    }
    [outline reloadData];if(first)[outline expandItem:nil expandChildren:YES];else for(NSString *path in [[folders allKeys] sortedArrayUsingSelector:@selector(compare:)])if([expanded containsObject:path])[outline expandItem:folders[path]];
    if(selectedPath){id leaf=leaves[selectedPath];NSInteger index=[outline rowForItem:leaf];if(index>=0)[outline selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];}
}
- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item {return item ? [item[@"children"] count]:self.treeRoots.count;}
- (id)outlineView:(NSOutlineView *)outline child:(NSInteger)index ofItem:(id)item {return item ? item[@"children"][index]:self.treeRoots[index];}
- (BOOL)outlineView:(NSOutlineView *)outline isItemExpandable:(id)item {return item[@"children"]!=nil;}
- (NSView *)outlineView:(NSOutlineView *)outline viewForTableColumn:(NSTableColumn *)column item:(id)item {
    if(item[@"material"]){NSUInteger index=[self.rows indexOfObjectIdenticalTo:item[@"material"]];return [self tableView:outline viewForTableColumn:column row:(NSInteger)index];}
    NSUInteger count=0,selected=0;NSString *prefix=[item[@"path"] stringByAppendingString:@"/"];for(NSDictionary *row in self.rows)if([row[@"path"] hasPrefix:prefix]){count++;if(![self.excluded containsObject:row[@"path"]])selected++;}
    NSTextField *label=Text([NSString stringWithFormat:@"%@ %@\n%lu／%lu 个文件",selected==count ? @"✓":(selected ? @"−":@"○"),[item[@"path"] lastPathComponent],(unsigned long)selected,(unsigned long)count],12,NSFontWeightMedium,Ink());label.maximumNumberOfLines=2;label.toolTip=item[@"path"];return label;
}
- (void)outlineViewSelectionDidChange:(NSNotification *)notification {[self tableViewSelectionDidChange:notification];}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table{return self.rows.count;}
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)index {NSDictionary *row=self.rows[index];NSString *path=row[@"path"];NSTextField *label=Text([NSString stringWithFormat:@"%@ %@\n%@",[self.excluded containsObject:path] ? @"○":@"✓",[path lastPathComponent],[row[@"requirements"] boolValue] ? @"题目依据":([row[@"image"] boolValue] ? @"图片":path.stringByDeletingLastPathComponent)],12,NSFontWeightRegular,Ink());label.maximumNumberOfLines=2;label.toolTip=path;return label;}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSDictionary *node=[self selectedNode];if(!node)return;NSDictionary *row=node[@"material"];
    self.include.title=row ? @"包含此文件":@"包含此目录";
    if(!row){NSString *prefix=[node[@"path"] stringByAppendingString:@"/"];NSUInteger count=0,selected=0;NSMutableString *listing=NSMutableString.string;for(NSDictionary *leaf in self.rows)if([leaf[@"path"] hasPrefix:prefix]){count++;BOOL included=![self.excluded containsObject:leaf[@"path"]];if(included)selected++;[listing appendFormat:@"%@ %@\n",included ? @"✓":@"○",leaf[@"path"]];}self.heading.stringValue=node[@"path"];self.heading.toolTip=node[@"path"];self.include.enabled=YES;self.include.allowsMixedState=YES;self.include.state=selected==count ? NSControlStateValueOn:(selected ? NSControlStateValueMixed:NSControlStateValueOff);self.image.image=nil;self.imageScroll.hidden=YES;self.text.enclosingScrollView.hidden=NO;self.text.string=[@"可展开目录逐文件审阅，或一次排除此目录。\n\n" stringByAppendingString:listing];[self.text scrollRangeToVisible:NSMakeRange(0,0)];[self updateSummary];return;}
    self.include.allowsMixedState=NO;NSString *path=row[@"path"];BOOL picture=[row[@"image"] boolValue];self.heading.stringValue=path;self.heading.toolTip=path;self.include.enabled=![row[@"requirements"] boolValue];self.include.state=[self.excluded containsObject:path] ? NSControlStateValueOff:NSControlStateValueOn;
    self.imageScroll.hidden=!picture;self.text.enclosingScrollView.hidden=picture;self.image.image=picture ? [[NSImage alloc] initWithData:self.snapshot[@"files"][path][@"data"]]:nil;self.fit=YES;self.zoom=1;
    if(picture){[self sizeImage];[self.imageScroll.documentView scrollPoint:NSZeroPoint];}else {NSString *value=[row[@"requirements"] boolValue] ? self.requirements:self.snapshot[@"files"][path][@"text"];NSArray *lines=[value componentsSeparatedByString:@"\n"];NSMutableString *display=NSMutableString.string;BOOL csv=[path.pathExtension.lowercaseString isEqual:@"csv"];NSUInteger limit=csv ? MIN(200,lines.count):lines.count;
        if(csv)[display appendFormat:@"数据表：共 %lu 行，预览前 %lu 行；发送时包含完整数据。\n\n",(unsigned long)lines.count,(unsigned long)limit];
        for(NSUInteger n=0;n<limit;n++)[display appendFormat:@"%4lu  %@\n",(unsigned long)n+1,lines[n]];self.text.string=display;self.text.selectedRange=NSMakeRange(0,0);[self.text scrollRangeToVisible:NSMakeRange(0,0)];}
    [self updateSummary];
}
- (void)updateSummary {NSUInteger count=0,images=0;for(NSDictionary *row in self.rows)if(![row[@"requirements"] boolValue] && ![self.excluded containsObject:row[@"path"]]){count++;if([row[@"image"] boolValue])images++;}self.summary.stringValue=[NSString stringWithFormat:@"已选 %lu 个文件 · %lu 张图片",(unsigned long)count,(unsigned long)images];}
- (void)toggle:(id)sender {
    NSDictionary *node=[self selectedNode];if(!node)return;BOOL include=self.include.state!=NSControlStateValueOff;NSString *path=node[@"path"],*prefix=[path stringByAppendingString:@"/"];
    for(NSDictionary *row in self.rows)if(![row[@"requirements"] boolValue] && ([row[@"path"] isEqual:path] || (!node[@"material"] && [row[@"path"] hasPrefix:prefix]))){if(include)[self.excluded removeObject:row[@"path"]];else [self.excluded addObject:row[@"path"]];}
    NSOutlineView *outline=(NSOutlineView *)self.table;[outline reloadItem:node reloadChildren:YES];for(NSDictionary *parent=[outline parentForItem:node];parent;parent=[outline parentForItem:parent])[outline reloadItem:parent];[self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self.table]];[self updateSummary];
}
- (void)tool:(NSButton *)sender {
    if(sender.tag>=4){NSInteger i=[self selectedIndex],j=i+(sender.tag==4 ? -1:1);if(i<0 || j<0 || j>=(NSInteger)self.rows.count || [self.rows[i][@"requirements"] boolValue] || [self.rows[j][@"requirements"] boolValue])return;NSString *path=self.rows[i][@"path"];[self.rows exchangeObjectAtIndex:i withObjectAtIndex:j];[self rebuildTree:path];return;}
    if(!self.image.image)return;if(sender.tag==0)self.fit=YES;else{if(self.fit)self.zoom=NSWidth(self.image.bounds)/MAX(1,self.image.image.size.width);self.fit=NO;self.zoom=sender.tag==1 ? 1:MIN(4,MAX(.1,self.zoom*(sender.tag==2 ? 1.4:1/1.4)));}[self sizeImage];
}
- (NSArray *)selectedImages {NSMutableArray *images=NSMutableArray.array;for(NSDictionary *row in self.rows)if([row[@"image"] boolValue] && ![self.excluded containsObject:row[@"path"]])[images addObject:row];return images;}
- (NSDictionary *)selectedSnapshot {NSMutableDictionary *snapshot=self.snapshot.mutableCopy;NSMutableArray *paths=NSMutableArray.array;for(NSDictionary *row in self.rows)if(![row[@"requirements"] boolValue] && ![row[@"image"] boolValue] && ![self.excluded containsObject:row[@"path"]])[paths addObject:row[@"path"]];snapshot[@"paths"]=paths;return snapshot;}
- (void)prepare:(id)sender {if(![self selectedImages].count && ![[self selectedSnapshot][@"paths"] count]){self.summary.stringValue=@"至少保留一个文档或图片。";return;}[NSApp stopModalWithCode:NSModalResponseOK];[self.window orderOut:nil];}
- (void)cancel:(id)sender {[NSApp stopModalWithCode:NSModalResponseCancel];[self.window orderOut:nil];}
- (BOOL)windowShouldClose:(NSWindow *)window {[self cancel:nil];return NO;}
@end
