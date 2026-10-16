- (void)configureRecurrence {
    NSDictionary *saved=nil;for(NSDictionary *s in self.appDelegate.recurrenceSeries)if([s[@"id"] isEqual:self.task[@"seriesID"]])saved=s[@"rule"];
    NSStackView *stack=self.recurrenceSection;stack.spacing=8;
    void (^add)(NSView *)=^(NSView *view){[stack addArrangedSubview:view];view.translatesAutoresizingMaskIntoConstraints=NO;[view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;};
    add(Text(@"重复",12,NSFontWeightMedium,Muted()));
    self.repeatMode=[[NSPopUpButton alloc] initWithFrame:NSZeroRect];[self.repeatMode addItemsWithTitles:@[@"不重复",@"按固定日历",@"完成后重复"]];[self.repeatMode selectItemAtIndex:[saved[@"mode"] isEqual:@"fixed"] ? 1:([saved[@"mode"] isEqual:@"completion"] ? 2:0)];add(self.repeatMode);
    self.repeatUnit=[[NSPopUpButton alloc] initWithFrame:NSZeroRect];[self.repeatUnit addItemsWithTitles:@[@"天",@"周",@"月",@"年"]];NSInteger unit=[@[@"day",@"week",@"month",@"year"] indexOfObject:saved[@"unit"] ?: @"week"];[self.repeatUnit selectItemAtIndex:unit==NSNotFound ? 1:unit];
    self.repeatInterval=[[PastelTextField alloc] initWithFrame:NSZeroRect];self.repeatInterval.stringValue=[saved[@"interval"] stringValue] ?: @"1";self.repeatInterval.delegate=self;self.repeatInterval.accessibilityLabel=@"重复间隔";
    NSStackView *frequency=[NSStackView stackViewWithViews:@[Text(@"每",13,NSFontWeightRegular,Ink()),self.repeatInterval,self.repeatUnit]];frequency.spacing=8;[self.repeatInterval.widthAnchor constraintEqualToConstant:72].active=YES;add(frequency);
    NSMutableArray *days=NSMutableArray.array;NSCalendar *calendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];calendar.timeZone=[NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    for(NSInteger i=0;i<7;i++){NSButton *b=[NSButton checkboxWithTitle:@[@"一",@"二",@"三",@"四",@"五",@"六",@"日"][i] target:self action:@selector(recurrenceChanged:)];b.tag=(i+1)%7+1;b.state=[(saved[@"weekdays"] ?: @[@([calendar component:NSCalendarUnitWeekday fromDate:self.selectedDate])]) containsObject:@(b.tag)] ? NSControlStateValueOn:NSControlStateValueOff;b.accessibilityLabel=[@"每周" stringByAppendingString:b.title];[days addObject:b];}self.repeatWeekdays=days;add([NSStackView stackViewWithViews:days]);
    self.holidayPolicy=[[NSPopUpButton alloc] initWithFrame:NSZeroRect];[self.holidayPolicy addItemsWithTitles:@[@"休息日保持原日期",@"跳过休息日",@"提前到上一工作日",@"顺延到下一工作日"]];NSUInteger policy=[@[@"keep",@"skip",@"previous",@"next"] indexOfObject:saved[@"holidayPolicy"] ?: @"keep"];[self.holidayPolicy selectItemAtIndex:policy==NSNotFound ? 0:policy];add(self.holidayPolicy);
    self.repeatEnd=[[NSPopUpButton alloc] initWithFrame:NSZeroRect];[self.repeatEnd addItemsWithTitles:@[@"一直重复",@"截至日期",@"限定次数（从本次起）"]];[self.repeatEnd selectItemAtIndex:saved[@"until"] ? 1:(saved[@"count"] ? 2:0)];add(self.repeatEnd);
    self.repeatUntil=NSDatePicker.new;self.repeatUntil.datePickerElements=NSDatePickerElementFlagYearMonthDay;self.repeatUntil.dateValue=saved[@"until"] ?: [calendar dateByAddingUnit:NSCalendarUnitYear value:1 toDate:self.selectedDate options:0];self.repeatUntil.target=self;self.repeatUntil.action=@selector(recurrenceChanged:);add(self.repeatUntil);
    self.repeatCount=[[PastelTextField alloc] initWithFrame:NSZeroRect];self.repeatCount.stringValue=saved[@"count"] ? [@(MAX(1,[saved[@"count"] integerValue]-[self.task[@"occurrenceIndex"] integerValue])) stringValue]:@"10";self.repeatCount.delegate=self;self.repeatCount.accessibilityLabel=@"重复总次数";add(self.repeatCount);
    self.seriesScope=[[NSPopUpButton alloc] initWithFrame:NSZeroRect];[self.seriesScope addItemsWithTitles:@[@"仅修改本次",@"修改本次及以后"]];if(saved)add(self.seriesScope);
    self.repeatPreview=Text(@"",12,NSFontWeightRegular,Muted());self.repeatPreview.maximumNumberOfLines=0;self.repeatPreview.selectable=YES;add(self.repeatPreview);
    for(NSPopUpButton *p in @[self.repeatMode,self.repeatUnit,self.holidayPolicy,self.repeatEnd,self.seriesScope]){p.target=self;p.action=@selector(recurrenceChanged:);}
    self.allowedUnknownYears=saved[@"allowedUnknownYears"] ?: @[];
    if(self.candidate || self.task[@"sourceID"] || self.task[@"sourceRepository"]){self.repeatMode.enabled=NO;add(Text(@"老师作业不直接重复。",12,NSFontWeightRegular,Muted()));}
    [self recurrenceChanged:nil];
}
- (NSDictionary *)recurrenceRule {
    if(self.repeatMode.indexOfSelectedItem==0)return nil;
    if([self.repeatInterval.stringValue rangeOfString:@"^[0-9]{1,4}$" options:NSRegularExpressionSearch].location==NSNotFound || (self.repeatEnd.indexOfSelectedItem==2 && [self.repeatCount.stringValue rangeOfString:@"^[0-9]{1,5}$" options:NSRegularExpressionSearch].location==NSNotFound))return @{};
    NSMutableDictionary *rule=[@{@"mode":self.repeatMode.indexOfSelectedItem==1 ? @"fixed":@"completion",@"unit":@[@"day",@"week",@"month",@"year"][self.repeatUnit.indexOfSelectedItem],@"interval":@(self.repeatInterval.integerValue),@"anchor":self.selectedDate,@"timeZone":@"Asia/Shanghai",@"holidayPolicy":@[@"keep",@"skip",@"previous",@"next"][self.holidayPolicy.indexOfSelectedItem],@"allowedUnknownYears":self.allowedUnknownYears ?: @[]} mutableCopy];
    if(self.repeatUnit.indexOfSelectedItem==1 && self.repeatMode.indexOfSelectedItem==1){NSMutableArray *days=NSMutableArray.array;for(NSButton *day in self.repeatWeekdays)if(day.state==NSControlStateValueOn)[days addObject:@(day.tag)];rule[@"weekdays"]=days;}
    if(self.repeatEnd.indexOfSelectedItem==1){NSCalendar *c=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];c.timeZone=[NSTimeZone timeZoneWithName:@"Asia/Shanghai"];rule[@"until"]=[c dateBySettingHour:23 minute:59 second:59 ofDate:self.repeatUntil.dateValue options:0];}else if(self.repeatEnd.indexOfSelectedItem==2)rule[@"count"]=@(self.repeatCount.integerValue);
    return rule;
}
- (void)recurrenceChanged:(id)sender {
    BOOL enabled=self.repeatMode.indexOfSelectedItem>0;
    self.repeatUnit.superview.hidden=!enabled;self.repeatWeekdays.firstObject.superview.hidden=!enabled || self.repeatUnit.indexOfSelectedItem!=1 || self.repeatMode.indexOfSelectedItem!=1;self.holidayPolicy.hidden=!enabled;self.repeatEnd.hidden=!enabled;self.repeatUntil.hidden=!enabled || self.repeatEnd.indexOfSelectedItem!=1;self.repeatCount.hidden=!enabled || self.repeatEnd.indexOfSelectedItem!=2;
    if(!enabled){self.repeatPreview.stringValue=self.task[@"seriesID"] ? @"选择“本次及以后”可停止后续重复；已完成记录保留。":@"";return;}
    NSError *error=nil;NSDictionary *r=[self recurrenceRule];NSCalendarUnit unit=[@[@(NSCalendarUnitDay),@(NSCalendarUnitWeekOfYear),@(NSCalendarUnitMonth),@(NSCalendarUnitYear)][self.repeatUnit.indexOfSelectedItem] unsignedIntegerValue];NSDate *end=[self.teacherCalendar dateByAddingUnit:unit value:MAX(1,self.repeatInterval.integerValue)*6 toDate:self.selectedDate options:0];
    // Preview completion-based schedules from the selected first deadline. Actual
    // successors are based on completion timestamps in the materializer.
    NSMutableDictionary *preview=r.mutableCopy;preview[@"count"]=@(MIN([r[@"count"] integerValue] ?: 5,5));preview[@"allowUnknownCalendar"]=@YES;
    NSArray *dates=DDLRecurrenceDates(preview,self.selectedDate,end,self.appDelegate.preview ? @{}:SSCalendarOverrides(),&error);
    NSMutableArray *labels=NSMutableArray.array;for(NSDictionary *d in dates){[labels addObject:[[self formatTeacherDate:d[@"due"]] stringByAppendingString:[DDLChinaDayInfo(d[@"due"],self.teacherCalendar,@{})[@"known"] boolValue] ? @"":@"（假期安排未收录）"]];if(labels.count==5)break;}
    self.repeatPreview.stringValue=error.localizedDescription ?: [NSString stringWithFormat:@"%@%@",self.repeatMode.indexOfSelectedItem==2 ? @"示例日期（后续实际以完成时间为准）：\n":@"接下来五次：\n",[labels componentsJoinedByString:@"\n"]];self.repeatPreview.textColor=error ? NSColor.systemOrangeColor:Muted();
}
