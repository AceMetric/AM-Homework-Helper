#import "AMWorkflow.h"
@interface AMCourseOperationContext:NSObject
@property(weak) SSCourseController *owner;
@property NSString *identifier;
@property NSString *noticeKey;
@property NSDictionary *course;
@property NSString *authType;
@property NSDictionary *authenticationIdentity;
@property NSError *failure;
@property(copy) void (^recovery)(void);
@property(copy) BOOL (^saveResult)(NSError **);
@property BOOL finished;
@property BOOL customResult;
@property NSString *sourceCommit;
@property SSGit *git;
@property SSGitHub *api;
@property AMCourseWorkKind kind;
@property(atomic) BOOL cancelled;
@property NSDate *enqueued;
@property NSString *stage;
@property NSString *lastStatus;
@property NSDictionary *problem;
@property NSDictionary *record;
@property SSSubmissionController *submissionDraft;
@end
@implementation AMCourseOperationContext @end
static NSDictionary *AMWorkflowSavedScan(NSDictionary *result){NSMutableDictionary *saved=result.mutableCopy;[saved removeObjectForKey:@"persistenceIssue"];if(saved[@"modelSummary"]){NSMutableDictionary *summary=[saved[@"modelSummary"] mutableCopy];summary[@"unsaved"]=@0;saved[@"modelSummary"]=summary;saved[@"modelCompleted"]=@([summary[@"failed"] unsignedIntegerValue]==0 && [summary[@"pending"] unsignedIntegerValue]==0);}return saved;}
static AMCourseOperationContext *AMCourseFailureContext(SSCourseController *owner,NSDictionary *course,SSGitHub *api,NSDictionary *authentication,NSError *error,NSDictionary *record){AMCourseOperationContext *context=AMCourseOperationContext.new;context.owner=owner;context.course=course;context.api=api;context.authenticationIdentity=authentication;context.failure=error;context.record=record;return context;}
static AMCourseOperationContext *AMCourseContext(id owner){AMCourseOperationContext *context=NSThread.currentThread.threadDictionary[@"AMCourseOperationContext"];return context.owner==owner ? context:nil;}
static void AMWithCourseContext(AMCourseOperationContext *context,void (^body)(void)){
    if(!context){body();return;}NSMutableDictionary *thread=NSThread.currentThread.threadDictionary;id prior=thread[@"AMCourseOperationContext"],parent=thread[@"AMOperationParent"],cancel=thread[@"AMOperationCancellation"];
    thread[@"AMCourseOperationContext"]=context;thread[@"AMOperationParent"]=context.identifier;thread[@"AMOperationCancellation"]=[^BOOL{return context.cancelled;} copy];
    @try{body();}@finally{for(NSArray *entry in @[@[@"AMCourseOperationContext",prior ?: NSNull.null],@[@"AMOperationParent",parent ?: NSNull.null],@[@"AMOperationCancellation",cancel ?: NSNull.null]]){if(entry[1]==NSNull.null)[thread removeObjectForKey:entry[0]];else thread[entry[0]]=entry[1];}}
}
@interface AMWorkflowNotice:NSVisualEffectView
@property NSTextField *label;
@property NSButton *actionButton;
@property(copy) void (^performRecovery)(void);
@property(copy) void (^performDetails)(void);
@property(copy) void (^dismissed)(void);
@end
@implementation AMWorkflowNotice
- (instancetype)initWithFrame:(NSRect)frame {if((self=[super initWithFrame:frame])){self.material=NSVisualEffectMaterialPopover;self.blendingMode=NSVisualEffectBlendingModeWithinWindow;self.wantsLayer=YES;self.layer.cornerRadius=10;
    self.label=Text(@"",13,NSFontWeightRegular,Ink());self.label.maximumNumberOfLines=2;self.label.lineBreakMode=NSLineBreakByWordWrapping;[self.label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSButton *close=[NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"关闭提示"] target:self action:@selector(dismiss:)];close.bordered=NO;close.toolTip=@"关闭提示";close.translatesAutoresizingMaskIntoConstraints=NO;[close.widthAnchor constraintEqualToConstant:24].active=YES;
    NSStackView *heading=[NSStackView stackViewWithViews:@[self.label,close]];heading.spacing=8;heading.alignment=NSLayoutAttributeTop;
    self.actionButton=[NSButton buttonWithTitle:@"" target:self action:@selector(recover:)];self.actionButton.bezelStyle=NSBezelStyleRounded;NSButton *details=[NSButton buttonWithTitle:@"详情" target:self action:@selector(details:)];details.bezelStyle=NSBezelStyleRounded;
    NSStackView *actions=[NSStackView stackViewWithViews:@[self.actionButton,details]];actions.spacing=8;
    NSStackView *body=[NSStackView stackViewWithViews:@[heading,actions]];body.orientation=NSUserInterfaceLayoutOrientationVertical;body.alignment=NSLayoutAttributeLeading;body.spacing=6;body.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:body];
    [NSLayoutConstraint activateConstraints:@[[body.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],[body.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],[body.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],[body.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],[heading.widthAnchor constraintEqualToAnchor:body.widthAnchor]]];
}return self;}
- (void)dismiss:(id)sender {self.hidden=YES;if(self.dismissed)self.dismissed();}
- (void)recover:(id)sender {if(self.performRecovery)self.performRecovery();}
- (void)details:(id)sender {if(self.performDetails)self.performDetails();}
@end

static NSString *AMScheduleCourseWorkflow(NSString *key,NSString *kind,NSString *target,NSArray *resources,NSInteger priority,BOOL cancellable,void (^start)(NSString *),void (^cancel)(BOOL)){
    NSMutableDictionary *thread=NSThread.currentThread.threadDictionary;id parent=thread[@"AMOperationParent"];[thread removeObjectForKey:@"AMOperationParent"];@try{return AMOperationSchedule(key,kind,target,resources,priority,cancellable,start,cancel);}@finally{if(parent)thread[@"AMOperationParent"]=parent;}
}
