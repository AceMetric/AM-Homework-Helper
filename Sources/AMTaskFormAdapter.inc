// Persistence adapters stay in the existing controller. The visible fields are
// shared with review/import; these legacy controls are never rendered twice.
- (NSDictionary *)sharedFormRecord {
    NSMutableDictionary *rule=[([self recurrenceRule] ?: @{}) mutableCopy];
    rule[@"mode"]=@[@"none",@"fixed",@"completion"][MAX(0,self.repeatMode.indexOfSelectedItem)];
    rule[@"intervalText"]=self.repeatInterval.stringValue ?: @"1";rule[@"countText"]=self.repeatCount.stringValue ?: @"10";rule[@"endMode"]=@(MAX(0,self.repeatEnd.indexOfSelectedItem));
    if(!rule[@"unit"])rule[@"unit"]=@"week";if(!rule[@"holidayPolicy"])rule[@"holidayPolicy"]=@"keep";if(!rule[@"weekdays"]){NSMutableArray *days=NSMutableArray.array;for(NSButton *day in self.repeatWeekdays)if(day.state==NSControlStateValueOn)[days addObject:@(day.tag)];rule[@"weekdays"]=days;}
    if(self.repeatUntil)rule[@"until"]=self.repeatUntil.dateValue;
    NSArray *catalog=AMCourseCatalog(self.appDelegate.courseWindow.submissionCourses ?: @[]);NSDictionary *course=AMCourseForTask(self.task ?: @{},catalog);if(!self.task && self.creationCourse.length)for(NSDictionary *row in catalog)if([row[@"id"] isEqual:self.creationCourse] || [row[@"fork"] isEqual:self.creationCourse])course=row;
    NSString *courseID=self.selectedCourseIdentity ?: course[@"id"] ?: @"";
    return @{@"supportsTime":@(!self.candidate && [self.task[@"id"] length]>0),@"reviewCandidate":@(self.candidate!=nil),@"subtaskSuggestions":[(self.candidate[@"suggestedSubtasks"] ?: @[]) arrayByAddingObjectsFromArray:self.candidate[@"additionalSubtaskSuggestions"] ?: @[]],@"subtasks":self.proposedSubtasks ?: self.task[@"subtasks"] ?: self.candidate[@"suggestedSubtasks"] ?: @[],@"courseID":courseID,@"timeZone":self.teacherCalendar.timeZone.name,@"title":self.titleField.stringValue ?: @"",@"subject":self.subjectField.stringValue ?: @"",@"due":self.selectedDate ?: NSDate.date,@"notes":self.notesField.string ?: @"",@"priority":@(MAX(0,self.priority.indexOfSelectedItem)),@"reminderOffsets":DDLParseReminderOffsets(self.reminderField.stringValue) ?: @[],@"recurrence":rule,@"seriesScope":@(MAX(0,self.seriesScope.indexOfSelectedItem)),@"series":@(self.task[@"seriesID"]!=nil),@"sourceLocked":@(!self.repeatMode.enabled),@"dateConfirmed":@(!self.candidate || self.dateExplicitlyConfirmed || self.task[@"due"]!=nil),@"dateHint":self.candidate && !self.dateExplicitlyConfirmed && !self.task[@"due"] ? @"截止日期和时间待确认":([self.candidate[@"deadlineText"] length] ? self.candidate[@"deadlineText"]:(self.calendarHint.stringValue ?: @"")),@"evidence":self.candidate[@"snippet"] ?: @"",@"saveTitle":self.candidate ? (self.reviewQueue.count ? @"保存并下一项":@"确认作业"):(self.task ? @"保存修改":@"添加任务"),@"isNew":@(self.task==nil),@"recurrencePreview":self.repeatPreview.stringValue ?: @"",@"overwriteSeriesExceptions":@(self.overwriteSeriesExceptions),@"planningSummary":[NSString stringWithFormat:@"%lu 项子任务",(unsigned long)[self.task[@"subtasks"] count]],@"supplementaryHeight":@(170+[self.task[@"subtasks"] count]*76)};
}
- (void)applySharedForm:(NSDictionary *)values {
    if(self.syncingSharedForm)return;self.syncingSharedForm=YES;self.proposedSubtasks=values[@"subtasks"];self.selectedCourseIdentity=values[@"courseID"];self.overwriteSeriesExceptions=[values[@"overwriteSeriesExceptions"] boolValue];
    self.titleField.stringValue=values[@"title"] ?: @"";self.subjectField.stringValue=values[@"subject"] ?: @"";self.notesField.string=values[@"notes"] ?: @"";
    self.reminderField.stringValue=DDLFormatReminderOffsets(values[@"reminderOffsets"] ?: @[]);[self.priority selectItemAtIndex:MAX(0,MIN(2,[values[@"priority"] integerValue]))];
    self.dateExplicitlyConfirmed=[values[@"dateConfirmed"] boolValue];if([values[@"due"] isKindOfClass:NSDate.class] && ![self.selectedDate isEqual:values[@"due"]])[self updateDate:values[@"due"]];
    NSDictionary *rule=values[@"recurrence"];
    if(self.repeatMode.enabled){NSUInteger mode=[@[@"none",@"fixed",@"completion"] indexOfObject:rule[@"mode"] ?: @"none"];[self.repeatMode selectItemAtIndex:mode==NSNotFound ? 0:mode];NSUInteger unit=[@[@"day",@"week",@"month",@"year"] indexOfObject:rule[@"unit"] ?: @"week"];[self.repeatUnit selectItemAtIndex:unit==NSNotFound ? 1:unit];self.repeatInterval.stringValue=rule[@"intervalText"] ?: @"1";self.repeatCount.stringValue=rule[@"countText"] ?: @"10";[self.repeatEnd selectItemAtIndex:MAX(0,MIN(2,[rule[@"endMode"] integerValue]))];if([rule[@"until"] isKindOfClass:NSDate.class])self.repeatUntil.dateValue=rule[@"until"];NSUInteger policy=[@[@"keep",@"skip",@"previous",@"next"] indexOfObject:rule[@"holidayPolicy"] ?: @"keep"];[self.holidayPolicy selectItemAtIndex:policy==NSNotFound ? 0:policy];for(NSButton *day in self.repeatWeekdays)day.state=[rule[@"weekdays"] containsObject:@(day.tag)] ? NSControlStateValueOn:NSControlStateValueOff;[self.seriesScope selectItemAtIndex:MAX(0,MIN(2,[values[@"seriesScope"] integerValue]))];}
    [self recurrenceChanged:nil];[self validateReminders];
    if(self.task[@"seriesID"] && [values[@"seriesScope"] integerValue]>0){NSMutableDictionary *edited=self.task.mutableCopy;for(NSString *key in @[@"title",@"subject",@"courseID",@"notes",@"priority",@"reminderOffsets"])if(values[key])edited[key]=values[key];NSDictionary *impact=DDLSeriesEdit(self.appDelegate.tasks,self.appDelegate.recurrenceSeries,self.task,edited,[values[@"seriesScope"] integerValue],self.overwriteSeriesExceptions);NSMutableDictionary *next=values.mutableCopy;BOOL schedule=![(self.initialRecurrence ?: @{}) isEqual:([self recurrenceRule] ?: @{})] || ![self.task[@"due"] isEqual:values[@"due"]];NSMutableSet *affected=[NSMutableSet setWithArray:impact[@"affectedIDs"] ?: @[]];if(schedule){NSString *family=DDLSeriesFamily(self.task[@"seriesID"],self.appDelegate.recurrenceSeries);NSDate *boundary=self.task[@"nominalDue"] ?: self.task[@"due"];for(NSDictionary *row in self.appDelegate.tasks)if([DDLSeriesFamily(row[@"seriesID"],self.appDelegate.recurrenceSeries) isEqual:family] && ![row[@"completed"] boolValue] && ![row[@"deleted"] boolValue] && [row[@"due"] timeIntervalSinceNow]>0 && ([values[@"seriesScope"] integerValue]==2 || [(row[@"nominalDue"] ?: row[@"due"]) compare:boundary]!=NSOrderedAscending))[affected addObject:row[@"id"]];}next[@"seriesImpact"]=[NSString stringWithFormat:@"影响 %lu 项现有记录，保留 %@ 个单独修改字段；历史日期不变%@",(unsigned long)affected.count,impact[@"skipped"],schedule ? @"，未来安排重新生成":@""];[self.sharedForm loadRecord:next resetBaseline:NO];}
self.syncingSharedForm=NO;[self layoutEditor];
}
- (void)installSharedForm {
    self.initialRecurrence=[self recurrenceRule];self.selectedCourseIdentity=[self sharedFormRecord][@"courseID"];self.proposedSubtasks=self.task[@"subtasks"] ?: self.candidate[@"suggestedSubtasks"] ?: @[];self.legacyEditorRoot=self.window.contentView;
    self.sharedForm=AMTaskFormController.new;[self.sharedForm loadRecord:[self sharedFormRecord] resetBaseline:YES];
    Surface *root=Box(Canvas(),0);root.frame=self.legacyEditorRoot.frame;self.window.contentView=root;
    self.sharedForm.view.frame=root.bounds;self.sharedForm.view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;[root addSubview:self.sharedForm.view];
    __weak typeof(self) owner=self;
    self.sharedForm.actionHandler=^(NSString *action,NSDictionary *record){
        EditorController *editor=owner;if(!editor)return;
        if([action isEqual:@"change"]){[editor applySharedForm:record];return;}
        if([action isEqual:@"save"]){[editor applySharedForm:record];if(editor.candidate && editor.reviewQueue.count)[editor saveAndReviewNext:nil];else [editor save:nil];return;}
        if([action isEqual:@"cancel"]){[editor.appDelegate requestCloseTaskEditor];return;}
        if([action isEqual:@"recognize"]){[editor.appDelegate quickEntry:nil];return;}
        if([action isEqual:@"time"]){AMShowTaskTime(editor.task,editor.window);return;}
        NSButton *sender=NSButton.new;sender.identifier=editor.task[@"id"];
        if([action isEqual:@"check"])[editor.appDelegate checkSelectedTask:sender];
        if([action isEqual:@"submit"] && [editor.appDelegate resolveTaskEditor])[editor.appDelegate submitSelectedTask:sender];
        if([action isEqual:@"history"] && [editor.appDelegate resolveTaskEditor])[editor.appDelegate taskSubmissionHistory:sender];
    };
    if(self.task && !self.candidate){
        AMTaskPlanningController *planner=AMTaskPlanningController.new;self.sharedPlanner=planner;[planner updateTask:self.task];
        planner.actionHandler=^(NSString *action,NSString *taskID,NSString *subID,NSString *value){AppDelegate *app=owner.appDelegate;if(![app resolveTaskEditor])return;[app planningAction:action task:taskID subtask:subID value:value];};
        [self.sharedForm setSupplementaryView:planner.view];
    }
    root.onResize=^{[owner layoutEditor];};self.window.initialFirstResponder=nil;self.window.defaultButtonCell=nil;
    ((DDLFormPanel *)self.window).onConfirm=^{[owner.sharedForm save];};((DDLFormPanel *)self.window).onCancel=^{[owner.appDelegate requestCloseTaskEditor];};
    [self layoutEditor];
}
- (void)reportSharedValidation {
    if(!self.sharedForm)return;
    NSString *message=self.validation.stringValue ?: @"";NSString *field=@"";
    if([message containsString:@"课程"])field=@"course";else if([message containsString:@"名称"])field=@"title";else if([message containsString:@"重复"] || [message containsString:@"周期"])field=@"recurrence";else if([message containsString:@"日期"] || [message containsString:@"时间"])field=@"date";else if([message containsString:@"提醒"])field=@"reminders";
    [self.sharedForm setValidation:message field:field];
}
