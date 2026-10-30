// 展示和编辑的是评分维度与分值，JSON、字段标识和版本散列只用于内部交换。
@interface AMRubricEditor : NSObject <NSTableViewDataSource,NSTableViewDelegate>
@property NSMutableArray *criteria;
@property NSTableView *table;
@property NSView *view;
- (instancetype)initWithRubric:(NSDictionary *)rubric;
@end
@implementation AMRubricEditor
- (instancetype)initWithRubric:(NSDictionary *)rubric {
    if(!(self=[super init]))return nil;
    self.criteria=NSMutableArray.array;
    for(NSDictionary *criterion in rubric[@"criteria"])[self.criteria addObject:criterion.mutableCopy];
    if(!self.criteria.count)[self.criteria addObject:[@{@"id":NSUUID.UUID.UUIDString,@"title":@"",@"maximum":@100} mutableCopy]];
    self.table=NSTableView.new;self.table.dataSource=self;self.table.delegate=self;self.table.rowHeight=30;
    for(NSString *key in @[@"title",@"maximum"]){NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:key];column.title=[key isEqual:@"title"] ? @"评分维度":@"满分";column.width=[key isEqual:@"title"] ? 380:100;column.editable=YES;[self.table addTableColumn:column];}
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,520,220)];scroll.documentView=self.table;scroll.hasVerticalScroller=YES;
    NSStackView *actions=[NSStackView stackViewWithViews:@[Button(@"添加维度",self,@selector(addCriterion:),0),Button(@"删除维度",self,@selector(removeCriterion:),0)]];actions.spacing=8;
    NSStackView *view=[NSStackView stackViewWithViews:@[scroll,actions,Text(@"双击修改维度和分值，满分合计须为100。",12,NSFontWeightRegular,Muted())]];view.orientation=NSUserInterfaceLayoutOrientationVertical;view.alignment=NSLayoutAttributeLeading;view.spacing=8;view.frame=NSMakeRect(0,0,520,284);[scroll.widthAnchor constraintEqualToConstant:520].active=YES;[scroll.heightAnchor constraintEqualToConstant:220].active=YES;self.view=view;return self;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table {return self.criteria.count;}
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {return self.criteria[row][column.identifier];}
- (void)tableView:(NSTableView *)table setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if([column.identifier isEqual:@"title"])self.criteria[row][@"title"]=[value description] ?: @"";
    else {NSScanner *scanner=[NSScanner scannerWithString:[value description] ?: @""];double number=0;self.criteria[row][@"maximum"]=[scanner scanDouble:&number] && scanner.isAtEnd && isfinite(number) ? @(number):@0;}
}
- (void)addCriterion:(id)sender {if(self.criteria.count>=30)return;[self.table.window makeFirstResponder:nil];[self.criteria addObject:[@{@"id":NSUUID.UUID.UUIDString,@"title":@"",@"maximum":@0} mutableCopy]];[self.table reloadData];[self.table editColumn:0 row:self.criteria.count-1 withEvent:nil select:YES];}
- (void)removeCriterion:(id)sender {NSInteger row=self.table.selectedRow;[self.table.window makeFirstResponder:nil];if(row>=0 && row<(NSInteger)self.criteria.count){[self.criteria removeObjectAtIndex:row];[self.table reloadData];}}
@end
