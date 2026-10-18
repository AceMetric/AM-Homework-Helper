- (void)changeOverviewMode:(NSSegmentedControl *)sender {self.weeklyMode=sender.selectedSegment==1;[self layout];}
- (void)renderWeekly {
    if(!self.weeklyController){self.weeklyController=AMWeeklyPlanningController.new;__weak typeof(self) owner=self;self.weeklyController.actionHandler=^(NSString *action,NSString *task,NSString *sub,NSString *date){[owner planningAction:action task:task subtask:sub value:date];};[self.root addSubview:self.weeklyController.view];}
    self.weeklyController.view.frame=self.scroll.frame;self.weeklyController.view.hidden=NO;
    NSMutableArray *sections=NSMutableArray.array;for(NSDictionary *section in DDLWeekSections(self.tasks,NSDate.date,self.weekOffset,Cal(),self.query ?: @"")){NSMutableDictionary *copy=section.mutableCopy;if(section[@"date"])copy[@"dayInfo"]=DDLChinaDayInfo(section[@"date"],Cal(),self.preview ? @{}:SSCalendarOverrides());[sections addObject:copy];}[self.weeklyController updateSections:sections notice:@""];
}
- (BOOL)confirmLatePlan:(NSString *)key task:(NSDictionary *)task {
    if([key compare:DDLPlanKey(task[@"due"],Cal())]!=NSOrderedDescending)return YES;
    NSAlert *warning=NSAlert.new;warning.messageText=@"计划日期晚于作业截止日期";warning.informativeText=@"这只调整你的工作安排，不会延长老师的截止时间或改变提醒。是否保留这个计划？";[warning addButtonWithTitle:@"保留计划"];[warning addButtonWithTitle:@"取消"];return [warning runModal]==NSAlertFirstButtonReturn;
}
- (BOOL)applyPlanning:(NSString *)action task:(NSString *)identifier subtask:(NSString *)subID value:(NSString *)value {
    NSDictionary *old=[self taskWithID:identifier];if(!old || [old[@"deleted"] boolValue])return NO;
    NSMutableDictionary *task=old.mutableCopy;NSMutableArray *children=NSMutableArray.array;for(NSDictionary *sub in old[@"subtasks"])[children addObject:sub.mutableCopy];
    NSUInteger index=[children indexOfObjectPassingTest:^BOOL(NSDictionary *sub,NSUInteger i,BOOL *stop){return [sub[@"id"] isEqual:subID];}];
    if(subID.length && index==NSNotFound){self.notice=@"这个子任务已变化，请重新选择。";[self render];return NO;}
    NSMutableDictionary *target=subID.length ? children[index]:task;
    if([action isEqual:@"set-plan"]){if(value.length && !DDLPlanDate(value,Cal())){self.notice=@"计划日期无效，未保存。";[self render];return NO;}if(value.length && ![self confirmLatePlan:value task:task])return NO;if(value.length)target[@"plannedDate"]=value;else[target removeObjectForKey:@"plannedDate"];}
    else if([action isEqual:@"add"] || [action isEqual:@"edit"]){NSString *title=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!title.length || title.length>500 || ([action isEqual:@"add"] && children.count>=500)){self.notice=@"请填写1—500字的名称；每份作业最多500个步骤。";[self render];return NO;}if([action isEqual:@"add"])[children addObject:[@{@"id":NSUUID.UUID.UUIDString,@"title":title,@"completed":@NO} mutableCopy]];else if(subID.length)target[@"title"]=title;else return NO;}
    else if([action isEqual:@"toggle"] && subID.length)target[@"completed"]=@(![target[@"completed"] boolValue]);
    else if([action isEqual:@"delete"] && subID.length)[children removeObjectAtIndex:index];
    else if(([action isEqual:@"up"] || [action isEqual:@"down"]) && subID.length){NSInteger destination=(NSInteger)index+([action isEqual:@"up"] ? -1:1);if(destination<0 || destination>=(NSInteger)children.count)return YES;[children exchangeObjectAtIndex:index withObjectAtIndex:(NSUInteger)destination];}
    else return NO;
    task[@"subtasks"]=children;if(task[@"seriesID"])task[@"occurrenceEdited"]=@YES;
    NSMutableArray *tasks=[[self snapshot] mutableCopy];NSUInteger position=[tasks indexOfObjectPassingTest:^BOOL(NSDictionary *item,NSUInteger i,BOOL *stop){return [item[@"id"] isEqual:identifier];}];if(position==NSNotFound)return NO;tasks[position]=task;
    NSError *error=nil;BOOL saved=[self replaceTasks:tasks action:[action isEqual:@"set-plan"] ? @"调整计划":@"修改子任务" error:&error];self.notice=saved ? @"已保存，可按 ⌘Z 撤销。":(error.localizedDescription ?: @"未能保存，请重试。");[self render];return saved;
}
- (void)planningAction:(NSString *)action task:(NSString *)identifier subtask:(NSString *)subID value:(NSString *)value {
    if([action isEqual:@"previous"] || [action isEqual:@"next"] || [action isEqual:@"current"]){self.weekOffset=[action isEqual:@"current"] ? 0:MAX(-5200,MIN(5200,self.weekOffset+([action isEqual:@"next"] ? 1:-1)));[self render];return;}
    NSDictionary *task=[self taskWithID:identifier];if(!task)return;
    if([action isEqual:@"select"]){NSButton *sender=NSButton.new;sender.identifier=identifier;[self selectTask:sender];return;}
    NSDictionary *target=task;for(NSDictionary *sub in task[@"subtasks"])if([sub[@"id"] isEqual:subID])target=sub;
    if([action isEqual:@"plan"]){NSAlert *alert=NSAlert.new;alert.messageText=@"安排到哪一天？";alert.informativeText=@"只设置计划完成日期，不改变作业截止时间或提醒。";NSDatePicker *picker=NSDatePicker.new;picker.frame=NSMakeRect(0,0,260,32);picker.datePickerElements=NSDatePickerElementFlagYearMonthDay;picker.datePickerStyle=NSDatePickerStyleTextFieldAndStepper;picker.calendar=Cal();picker.dateValue=DDLPlanDate(target[@"plannedDate"],Cal()) ?: NSDate.date;alert.accessoryView=picker;[alert addButtonWithTitle:@"保存计划"];[alert addButtonWithTitle:@"取消"];[alert addButtonWithTitle:@"取消安排"];
        while(YES){NSInteger response=[alert runModal];if(response==NSAlertSecondButtonReturn)return;NSString *key=response==NSAlertThirdButtonReturn ? @"":DDLPlanKey(picker.dateValue,Cal());if([self applyPlanning:@"set-plan" task:identifier subtask:subID value:key])return;alert.informativeText=self.notice ?: @"未保存，请重试或取消。";} }
    if([action isEqual:@"add"] || [action isEqual:@"edit"]){NSAlert *alert=NSAlert.new;alert.messageText=[action isEqual:@"add"] ? @"添加子任务":@"编辑子任务";alert.informativeText=@"子任务沿用作业截止时间。";NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,320,28)];field.stringValue=[action isEqual:@"edit"] ? target[@"title"]:@"";field.placeholderString=@"子任务名称";alert.accessoryView=field;[alert addButtonWithTitle:@"保存"];[alert addButtonWithTitle:@"取消"];
        while([alert runModal]==NSAlertFirstButtonReturn){if([self applyPlanning:action task:identifier subtask:subID value:field.stringValue])return;alert.informativeText=self.notice ?: @"未保存，请重试或取消。";}return;}
    [self applyPlanning:action task:identifier subtask:subID value:value];
}
- (void)planTask:(id)sender {[self planningAction:@"plan" task:[self identifierForSender:sender] subtask:@"" value:@""];}
