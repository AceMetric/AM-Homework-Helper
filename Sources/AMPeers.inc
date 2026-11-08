#import "AMPeerCore.h"
#import <PDFKit/PDFKit.h>
#import <ImageIO/ImageIO.h>
#import "AMRubricUI.inc"

// 先检查像素尺寸再解码远端图片，避免很小的压缩文件造成无界内存分配；转为 PNG 也移除元数据。
static NSData *AMPeerImagePNG(NSData *bytes){
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)bytes,NULL);if(!source)return nil;
    NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));double width=[properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue],height=[properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
    if(width<=0 || height<=0 || width*height>50000000){CFRelease(source);return nil;}
    NSDictionary *options=@{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@2000};
    CGImageRef image=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)options);CFRelease(source);if(!image)return nil;NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithCGImage:image];CGImageRelease(image);return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}
static NSString *const AMGradePromptVersion=@"peer-grading-v1";
@interface AMPeerScopePicker : NSObject <NSSearchFieldDelegate>
@property(weak) NSPopUpButton *picker;
@property(weak) NSButton *openButton;
@property NSArray *sources;
@property NSArray *matches;
- (void)filter:(NSString *)query;
@end
@implementation AMPeerScopePicker
- (void)controlTextDidChange:(NSNotification *)notification {[self filter:[notification.object stringValue]];}
- (void)filter:(NSString *)query {
    NSMutableArray *matches=NSMutableArray.array;
    [self.picker removeAllItems];
    for(NSDictionary *row in self.sources){
        NSString *label=[NSString stringWithFormat:@"%@ · %@ · %@",row[@"title"],[row[@"course"][@"fork"] lastPathComponent],row[@"path"]];
        if(query.length && ![label localizedStandardContainsString:query])continue;
        [matches addObject:row];
        [self.picker addItemWithTitle:label];
    }
    self.matches=matches.copy;
    self.openButton.enabled=matches.count>0;
}
@end
@interface AMPeerCheckSelection : NSObject
@property NSArray *checks;
- (void)toggle:(NSButton *)sender;
@end
@implementation AMPeerCheckSelection
- (void)toggle:(NSButton *)sender {for(NSButton *check in self.checks)check.state=sender.state;}
@end


@interface AMPeerWindowController : NSWindowController <NSWindowDelegate>
@property NSDictionary *course;
@property NSDictionary *identity;
@property NSString *scope;
@property NSString *sourcePath;
@property NSString *selected;
@property NSString *selectedFile;
@property NSString *status;
@property NSMutableArray *peers;
@property NSArray *scoreSnapshot;
@property NSUInteger scoreRevision;
@property BOOL discoveringRubric;
@property BOOL batchGrading;
@property BOOL grading;
@property BOOL loadingPage;
@property NSArray *automaticReferences;
@property NSUInteger rubricRequestsUsed;
@property NSString *rubricModelIdentity;
@property NSMutableDictionary *browseSnapshots;
@property NSCache *previewCache;
@property AMDocumentView *documentReader;
@property SSGitHub *currentPreviewRequest;
@property BOOL identityCheckInFlight;
@property NSMutableDictionary *snapshots;
@property NSMutableDictionary *feedback;
@property NSMutableDictionary *materialCache;
@property NSArray *references;
@property NSDictionary *rubric;
@property NSString *provider;
@property NSDictionary *modelSettings;
@property NSUInteger page;
@property BOOL more;
@property NSUInteger generation;
@property NSUInteger previewGeneration;
@property NSUInteger browseGeneration;
@property NSUInteger active;
@property NSInteger filter;
@property NSUInteger requestLimit;
@property NSUInteger requestsUsed;
@property NSMutableArray *clients;
@property SSRecognitionClient *scoreClient;
@property AMOnlineReviewClient *gemini;
@property AMPeerController *workspace;
@property NSOperationQueue *queue;
@property NSOperationQueue *previewQueue;
@property NSDate *queriedAt;
@property BOOL closing;
@property NSTimer *identityTimer;
@property NSString *activityID;
@property BOOL groupFailed;
@property NSDictionary *rankingGroup;
@property BOOL associatingLLM;
@property NSMutableDictionary *evaluationStates;
@property NSMutableDictionary *peerMetadataCache;
- (void)associateFeedback;
- (void)addMaterials;
- (void)editRubric;
- (void)generateRubric;
- (void)grade;
- (void)importScore;
- (void)showScore;
- (void)removeMaterials;
- (void)removeEvaluation;
- (NSDictionary *)commentForPeer:(NSString *)identifier;
- (NSString *)inputVersion:(NSString *)identifier;
- (NSString *)evaluationKey:(NSDictionary *)row;
- (BOOL)evaluationCurrent:(NSDictionary *)row;
- (NSDictionary *)evaluationChecks:(NSString *)identifier snapshot:(NSDictionary *)snapshot api:(SSGitHub *)api;
- (NSDictionary *)snapshotForPeer:(NSString *)identifier;
- (NSArray *)comparableScores:(NSString *)identifier;
@end

@implementation AMPeerWindowController
- (instancetype)initWithCourse:(NSDictionary *)course scope:(NSString *)scope source:(NSString *)source {
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1120,720) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    if(!(self=[super initWithWindow:window]))return nil;window.title=@"同学作业";window.contentMinSize=NSMakeSize(600,460);window.releasedWhenClosed=NO;window.delegate=self;
    self.course=course.copy;self.scope=scope;self.sourcePath=source;self.identity=SSGitHub.new.authenticationIdentity;self.peers=NSMutableArray.array;self.snapshots=NSMutableDictionary.dictionary;self.feedback=NSMutableDictionary.dictionary;self.materialCache=NSMutableDictionary.dictionary;self.clients=NSMutableArray.array;self.references=@[];self.queue=NSOperationQueue.new;self.queue.maxConcurrentOperationCount=3;self.previewQueue=NSOperationQueue.new;self.previewQueue.maxConcurrentOperationCount=2;self.requestLimit=4;self.provider=@"local";self.modelSettings=SSRecognitionSettings();if([self.modelSettings[@"mode"] isEqual:@"cloud"])self.provider=@"cloud";
    self.browseSnapshots=NSMutableDictionary.dictionary;self.previewCache=NSCache.new;self.previewCache.totalCostLimit=64*1024*1024;self.previewCache.countLimit=32;self.peerMetadataCache=NSMutableDictionary.dictionary;self.evaluationStates=NSMutableDictionary.dictionary;self.workspace=AMPeerController.new;window.contentViewController=self.workspace;__weak typeof(self) weak=self;self.workspace.actionHandler=^(NSString *action,NSString *identifier){[weak action:action identifier:identifier];};
    NSDictionary *allSettings=SSReadPlist(@"peer-settings.plist");NSDictionary *stored=AMPeerSettingsValid(allSettings ?: @{}) ? allSettings[[self scopeKey]]:nil;self.rubric=AMPeerRubric(stored[@"rubric"],NULL);if(stored[@"provider"])self.provider=stored[@"provider"];if(stored[@"requestLimit"])self.requestLimit=[stored[@"requestLimit"] unsignedIntegerValue];
    id references=SSReadPlist([NSString stringWithFormat:@"peer-materials-%@.plist",[self scopeKey]]);if(AMPeerMaterialsValid(references))self.references=references;
    self.identityTimer=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){AMPeerWindowController *sheet=weak;if(!sheet || sheet.identityCheckInFlight)return;sheet.identityCheckInFlight=YES;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSDictionary *identity=SSGitHub.new.authenticationIdentity;dispatch_async(dispatch_get_main_queue(),^{AMPeerWindowController *owner=weak;if(!owner)return;owner.identityCheckInFlight=NO;if(![owner.identity isEqual:identity]){[owner stop];[owner.workspace setPreviewView:nil];@synchronized(owner){[owner.peers removeAllObjects];[owner.snapshots removeAllObjects];[owner.browseSnapshots removeAllObjects];[owner.previewCache removeAllObjects];owner.scoreSnapshot=@[];}[owner.materialCache removeAllObjects];owner.status=@"账户已变化，请重新打开同学作业";[owner present];}});});}];[self reloadScores];[self present];return self;
}
- (NSString *)scopeKey {return AMPeerHash(@[self.identity,self.course[@"upstreamID"] ?: @0,self.scope]);}
- (NSString *)modelIdentity {return [self.provider isEqual:@"gemini"] ? AMOnlineReviewCurrentModel():[NSString stringWithFormat:@"%@|%@",self.modelSettings[@"endpoint"] ?: @"",self.modelSettings[@"model"] ?: @""];}
- (BOOL)isCurrent:(NSUInteger)generation {return !self.closing && self.generation==generation;}
- (NSDictionary *)peer:(NSString *)identifier {@synchronized(self){for(NSDictionary *peer in self.peers)if([peer[@"repository"] isEqual:identifier])return peer;return nil;}}
- (NSDictionary *)snapshotForPeer:(NSString *)identifier {@synchronized(self){return self.snapshots[identifier ?: @""];}}
- (NSArray *)comparableScores:(NSString *)identifier {
    NSMutableArray *scores=NSMutableArray.array;
    for(NSDictionary *score in [self savedScores])if([score[@"repository"] isEqual:identifier] && ([score[@"kind"] isEqual:@"teacher"] || [score[@"inputVersion"] isEqual:[self inputVersion:identifier]])){
        BOOL sourceValid=YES;
        if([@[@"teacher",@"llm-external"] containsObject:score[@"kind"]])sourceValid=[self evaluationCurrent:score];
        if([score[@"kind"] isEqual:@"llm-teacher"])sourceValid=[self evaluationCurrent:[self commentForPeer:identifier]];
        if(score[@"remoteSources"])sourceValid=sourceValid && [self evaluationCurrent:score];if(sourceValid)[scores addObject:score];
    }
    return scores;
}
- (NSArray *)savedScores {@synchronized(self){return self.scoreSnapshot ?: @[];}}
- (void)reloadScores {
    __weak typeof(self) owner=self;NSString *scope=[self scopeKey];NSUInteger generation=self.generation,revision=self.scoreRevision;
    [self.queue addOperationWithBlock:^{id value=SSReadPlist(@"peer-evaluations.plist");BOOL exists=[NSFileManager.defaultManager fileExistsAtPath:[SSDataDirectory() URLByAppendingPathComponent:@"peer-evaluations.plist"].path];BOOL valid=(!value && !exists) || AMPeerScoresValid(value);
        dispatch_async(dispatch_get_main_queue(),^{AMPeerWindowController *sheet=owner;if(!sheet || ![sheet isCurrent:generation])return;if(valid){@synchronized(sheet){if(sheet.scoreRevision==revision)sheet.scoreSnapshot=value[scope] ?: @[];}}else sheet.status=@"评分记录无法读取，原文件保留";[sheet present];});
    }];
}
- (BOOL)saveScore:(NSDictionary *)score error:(NSError **)error {
    @synchronized(NSFileManager.defaultManager){id old=SSReadPlist(@"peer-evaluations.plist");if((!old && [NSFileManager.defaultManager fileExistsAtPath:[SSDataDirectory() URLByAppendingPathComponent:@"peer-evaluations.plist"].path]) || (old && !AMPeerScoresValid(old))){if(error)*error=AMPeerError(@"评分记录无法读取，原文件保留");return NO;}NSMutableDictionary *all=[old mutableCopy] ?: NSMutableDictionary.dictionary;NSMutableArray *rows=[old[[self scopeKey]] mutableCopy] ?: NSMutableArray.array;[rows addObject:score];all[[self scopeKey]]=rows;if(!AMPeerScoresValid(all)){if(error)*error=AMPeerError(@"评分记录校验未通过，未写入");return NO;}BOOL saved=SSWritePlist(@"peer-evaluations.plist",all,error);if(saved){@synchronized(self){self.scoreSnapshot=rows.copy;self.scoreRevision++;}}if(saved && [score[@"sourceVerifiedAt"] isKindOfClass:NSDate.class]){@synchronized(self.evaluationStates){self.evaluationStates[[self evaluationKey:score]]=@"current";}}return saved;}
}
- (void)present {
    // 排名批次与生成配置分开：查看已有模型的评分不应要求重新调用或安装该模型。
    NSMutableArray *groups=[NSMutableArray arrayWithObject:@{@"id":@"current",@"title":@"当前评分配置"}];NSMutableSet *groupIDs=NSMutableSet.set;
    for(NSDictionary *score in [self savedScores])if([score[@"kind"] hasPrefix:@"llm"]){NSDictionary *group=@{@"rubric":score[@"rubric"],@"model":score[@"model"],@"prompt":score[@"prompt"]};NSString *key=AMPeerHash(group);if([groupIDs containsObject:key])continue;[groupIDs addObject:key];NSMutableDictionary *item=group.mutableCopy;item[@"id"]=key;item[@"title"]=[NSString stringWithFormat:@"%@ · %@",score[@"model"],[NSString stringWithFormat:@"批次%lu",(unsigned long)groups.count]];[groups addObject:item];}
    NSMutableArray *rows=NSMutableArray.array;NSUInteger found=0,unknown=0;
    for(NSDictionary *peer in self.peers){NSMutableDictionary *row=peer.mutableCopy;row[@"id"]=peer[@"repository"];NSDictionary *snapshot=self.snapshots[peer[@"repository"]];row[@"state"]=snapshot[@"state"] ?: peer[@"state"] ?: @"待核验";if([row[@"state"] isEqual:@"发现作答"])found++;else if(![row[@"state"] isEqual:@"未发现作答"])unknown++;
        NSArray *scores=[self comparableScores:peer[@"repository"]];NSDictionary *score=AMPeerEffectiveScoreForSnapshot(scores,snapshot ?: @{},self.rankingGroup[@"rubric"] ?: self.rubric[@"version"] ?: @"",self.rankingGroup[@"model"] ?: [self modelIdentity],self.rankingGroup[@"prompt"] ?: AMGradePromptVersion);
        if(score){NSMutableDictionary *display=score.mutableCopy;display[@"display"]=[NSString stringWithFormat:@"%@/%@",score[@"score"],score[@"maximum"]];display[@"label"]=[score[@"kind"] isEqual:@"teacher"] ? @"老师评分":([score[@"kind"] isEqual:@"llm-teacher"] ? @"LLM · 参考老师评语":([score[@"kind"] isEqual:@"llm-external"] ? @"LLM · 外部记录":@"LLM评分"));row[@"effectiveScore"]=display;}else{BOOL hadScore=NO;for(NSDictionary *old in [self savedScores])if([old[@"repository"] isEqual:peer[@"repository"]] && ![old[@"kind"] isEqual:@"comment"])hadScore=YES;row[@"scoreStatus"]=hadScore ? @"已有其他批次或待核验评分":@"未评分";}
        if(self.filter==1 && ![score[@"kind"] isEqual:@"teacher"])continue;if(self.filter==2 && (!score || [score[@"kind"] isEqual:@"teacher"]))continue;[rows addObject:row];
    }
    NSArray *ordered=AMPeerRank(rows);BOOL teacherScore=NO,llmScore=NO;for(NSDictionary *row in ordered){if([row[@"effectiveScore"][@"kind"] isEqual:@"teacher"])teacherScore=YES;else if(row[@"effectiveScore"])llmScore=YES;}NSMutableArray *files=NSMutableArray.array;for(NSDictionary *file in (self.browseSnapshots[self.selected ?: @""] ?: self.snapshots[self.selected ?: @""])[@"files"]){NSMutableDictionary *copy=file.mutableCopy;copy[@"id"]=file[@"path"];[files addObject:copy];}
    NSString *summary=[NSString stringWithFormat:@"可见仓库 %lu · 发现作答 %lu · 待核验 %lu%@%@",(unsigned long)self.peers.count,(unsigned long)found,(unsigned long)unknown,self.more ? @" · 列表未完整":@"",self.queriedAt ? [@" · " stringByAppendingString:DDLFormatDate(self.queriedAt,@"M/d HH:mm")]:@""];
    [self.workspace updateState:@{@"title":[NSString stringWithFormat:@"%@ · %@",self.course[@"fork"],self.scope],@"summary":summary,@"status":self.status ?: @"",@"peers":ordered,@"files":files,@"selected":self.selected ?: @"",@"selectedFile":self.selectedFile ?: @"",@"more":@(self.more),@"busy":@(self.active>0),@"loadingPage":@(self.loadingPage),@"feedbackAvailable":@([self.feedback[self.selected ?: @""] count]>0),@"filter":@(self.filter),@"mixed":@(teacherScore && llmScore),@"groups":groups,@"groupID":self.rankingGroup ? AMPeerHash(self.rankingGroup):@"current"}];
}
- (void)showError:(NSError *)error {self.groupFailed=YES;self.status=error.localizedDescription ?: @"未完成，已有结果保留";[self present];}
- (void)run:(NSString *)title queue:(NSOperationQueue *)queue work:(id(^)(SSGitHub *,NSError **))work done:(void(^)(id,NSError *))done {
    // 完成回调可能直接衔接下一阶段，此时复用原活动，避免留下“准备中”的孤立记录。
    __weak typeof(self) weak=self;if(!self.activityID){self.groupFailed=NO;self.activityID=AMOperationBeginWithExitPolicy(@"同学作业",self.course[@"fork"],YES,NO,^{[weak stop];});}NSString *activity=self.activityID;AMOperationProgress(activity,title,0,0);
    NSUInteger generation=self.generation;SSGitHub *api=SSGitHub.new;api.expectedReadIdentity=self.identity;api.peerImmutableCache=self.peerMetadataCache;if(queue==self.previewQueue && [title isEqual:@"读取所选文件…"]){self.currentPreviewRequest.requestsCancelled=YES;self.currentPreviewRequest=api;}[self.clients addObject:api];self.active++;self.status=title;[self present];
    [queue addOperationWithBlock:^{NSError *error=nil;id result=[weak isCurrent:generation] ? work(api,&error):nil;BOOL identityCurrent=[api.expectedReadIdentity isEqual:api.authenticationIdentity];dispatch_async(dispatch_get_main_queue(),^{AMPeerWindowController *owner=weak;if(!owner)return;[owner.clients removeObject:api];if(![owner isCurrent:generation])return;if(!identityCurrent){[owner stop];[owner.workspace setPreviewView:nil];owner.status=@"账户已变化，请重新打开同学作业";[owner present];return;}owner.active=owner.active>0 ? owner.active-1:0;owner.groupFailed|=error!=nil;done(result,error);if(!owner.active && [owner.activityID isEqual:activity]){AMOperationFinish(activity,owner.groupFailed ? @"failed":@"completed",owner.status ?: @"查询已完成");owner.activityID=nil;}[owner present];});}];
}
- (void)stop {self.generation++;self.discoveringRubric=NO;self.grading=NO;self.loadingPage=NO;for(SSGitHub *api in self.clients)api.requestsCancelled=YES;self.scoreClient.scoringCancelled=YES;[self.gemini cancelImmediately];[self.queue cancelAllOperations];[self.previewQueue cancelAllOperations];[self.clients removeAllObjects];self.active=0;self.status=@"已停止 · 完整结果保留";AMOperationFinish(self.activityID,@"cancelled",self.status);self.activityID=nil;[self present];}
- (void)windowWillClose:(NSNotification *)notification {self.closing=YES;[self.identityTimer invalidate];[self stop];[self.materialCache removeAllObjects];}
- (void)loadPage:(NSUInteger)page {
    if(self.loadingPage)return;self.loadingPage=YES;
    [self run:@"读取可见仓库…" queue:self.queue work:^id(SSGitHub *api,NSError **error){return [api peerForks:self.course page:page error:error];} done:^(NSDictionary *value,NSError *error){self.loadingPage=NO;if(!value){[self showError:error];return;}NSMutableSet *ids=NSMutableSet.set;for(NSDictionary *row in self.peers)[ids addObject:row[@"repository"]];@synchronized(self){for(NSDictionary *row in value[@"peers"])if(![ids containsObject:row[@"repository"]])[self.peers addObject:row];}self.page=page;self.more=[value[@"more"] boolValue];self.queriedAt=value[@"queriedAt"];self.status=@"选择同学查看；可核验本页作答进度";}];
}
- (void)verifyPeer:(NSString *)identifier completion:(void(^)(NSDictionary *))completion {
    NSDictionary *original=[self peer:identifier];NSMutableDictionary *peer=original.mutableCopy;if(!peer)return;
    BOOL discover=[self.selected isEqual:identifier];
    NSString *pinned=self.browseSnapshots[identifier][@"commit"];if(AMPeerSHA(pinned))peer[@"branch"]=pinned;
    [self run:@"核验作答版本…" queue:self.queue work:^id(SSGitHub *api,NSError **error){NSMutableDictionary *teacher=[[api readableTeacher:self.course error:error] mutableCopy];if(self.sourcePath)teacher[@"sourcePath"]=self.sourcePath;NSDictionary *snapshot=teacher ? [api peerSnapshot:peer teacher:teacher scope:self.scope error:error]:nil;if(!snapshot)return nil;NSArray *feedback=discover ? [self discoverEvaluationsForPeer:original snapshot:snapshot teacher:teacher api:api]:@[];return @{@"snapshot":snapshot,@"evaluations":[self evaluationChecks:identifier snapshot:snapshot api:api],@"feedback":feedback};} done:^(NSDictionary *value,NSError *error){
        NSDictionary *snapshot=value[@"snapshot"];
        NSString *current=self.browseSnapshots[identifier][@"commit"];
        if(current && ![current isEqual:pinned] && ![current isEqual:snapshot[@"commit"]]){if(completion)completion(nil);return;}
        NSMutableDictionary *saved=snapshot.mutableCopy ?: [@{@"state":@"待核验",@"error":error.localizedDescription ?: @"仓库关联无法核验"} mutableCopy];if([error.userInfo[@"SSIssue"] isEqual:@"permission"] || [error.userInfo[@"AMIssue"] isEqual:@"permission"])saved[@"state"]=@"无法访问";@synchronized(self){self.snapshots[identifier]=saved;}if(discover && value[@"feedback"])self.feedback[identifier]=value[@"feedback"];if(value[@"evaluations"]){@synchronized(self.evaluationStates){[self.evaluationStates addEntriesFromDictionary:value[@"evaluations"]];}}NSUInteger pending=0;for(NSString *state in [value[@"evaluations"] allValues])if(![state isEqual:@"current"])pending++;self.status=snapshot ? (pending ? [NSString stringWithFormat:@"作答已核验 · %lu条评价待核验",(unsigned long)pending]:@"作答已核验"):saved[@"error"];if(completion)completion(snapshot);}];
}
- (NSDictionary *)loadFile:(NSDictionary *)file peer:(NSDictionary *)peer api:(SSGitHub *)api error:(NSError **)error {
    if(SSSensitivePath(file[@"path"]) || [file[@"size"] unsignedLongLongValue]>20*1024*1024){if(error)*error=AMPeerError(@"文件不适合应用内读取，请在 GitHub 查看");return nil;}
    NSData *bytes=[api peerBlob:file[@"sha"] repository:peer[@"repository"] error:error];if(!bytes || SSContainsSecret(bytes)){if(error && !*error)*error=AMPeerError(@"文件含疑似凭据，未载入");return nil;}
    NSString *text=[[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];NSMutableDictionary *entry=[@{@"data":bytes,@"version":file[@"sha"],@"path":file[@"path"]} mutableCopy];
    // NSImage 也能读取 PDF，但只取首张图会丢页；PDF 始终交给 PDFKit 的逐页处理。
    if([[[file[@"path"] pathExtension] lowercaseString] isEqual:@"pdf"])entry[@"pdf"]=@YES;
    else if(text){entry[@"text"]=[[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];}
    else{NSData *png=AMPeerImagePNG(bytes);if(png){entry[@"data"]=png;entry[@"image"]=@YES;}else{if(error)*error=AMPeerError(@"此二进制文件或图片尺寸不支持预览与完整评分");return nil;}}
    return entry;
}
- (void)browsePeer:(NSString *)identifier refreshing:(BOOL)refresh {
    NSDictionary *peer=[self peer:identifier];
    if(!peer)return;
    NSUInteger generation=++self.browseGeneration;
    BOOL samePeer=[self.selected isEqual:identifier];
    if(!samePeer){
        self.previewGeneration++;
        self.currentPreviewRequest.requestsCancelled=YES;
        [self.workspace setPreviewView:nil];
        self.selected=identifier;
        self.selectedFile=nil;
    }
    NSDictionary *cached=self.browseSnapshots[identifier];
    if(cached && !refresh){
        if(!samePeer || !self.selectedFile)[self openMainFile:cached];
        [self present];
        return;
    }
    [self run:@"读取作业文件夹…" queue:self.previewQueue work:^id(SSGitHub *api,NSError **error){
        return [api peerBrowseSnapshot:peer teacherID:self.course[@"upstreamID"] scope:self.scope error:error];
    } done:^(NSDictionary *snapshot,NSError *error){
        if(generation!=self.browseGeneration || ![self.selected isEqual:identifier])return;
        if(!snapshot){[self showError:error];return;}
        self.browseSnapshots[identifier]=snapshot;
        // 刷新时保持当前文件可读，直到新的提交确实改变了这个文件。
        if(![cached[@"commit"] isEqual:snapshot[@"commit"]]){
            @synchronized(self){self.snapshots[identifier]=nil;}
            NSString *path=self.selectedFile;
            NSDictionary *oldFile=nil,*newFile=nil;
            for(NSDictionary *file in cached[@"files"])if([file[@"path"] isEqual:path])oldFile=file;
            for(NSDictionary *file in snapshot[@"files"])if([file[@"path"] isEqual:path])newFile=file;
            if(newFile){
                if(![oldFile[@"sha"] isEqual:newFile[@"sha"]] || [path.pathExtension.lowercaseString isEqual:@"md"])[self previewFile:path];
            }else {
                self.selectedFile=nil;
                [self openMainFile:snapshot];
            }
        }
        [self verifyPeer:identifier completion:nil];
    }];
}
- (void)openMainFile:(NSDictionary *)snapshot {
    NSMutableArray *likely=NSMutableArray.array;
    for(NSDictionary *row in snapshot[@"files"]){
        NSString *path=row[@"path"],*stem=path.lastPathComponent.stringByDeletingPathExtension.lowercaseString;
        if([row[@"directory"] boolValue] || [path isEqual:self.sourcePath])continue;
        if([@[@"answer",@"solution",@"assignment",@"答案",@"解答",self.scope.lastPathComponent.lowercaseString] containsObject:stem])[likely addObject:path];
    }
    if(likely.count==1)[self previewFile:likely.firstObject];
    else [self.workspace setPreviewView:nil];
}
- (void)previewFile:(NSString *)path {
    NSString *identifier=self.selected;
    NSDictionary *snapshot=self.browseSnapshots[identifier] ?: self.snapshots[identifier],*peer=[self peer:identifier],*file=nil;
    for(NSDictionary *row in snapshot[@"files"])if([row[@"path"] isEqual:path]){file=row;break;}
    if(!file)return;
    NSUInteger preview=++self.previewGeneration;
    if([file[@"directory"] boolValue]){
        [self run:@"读取作业文件夹…" queue:self.previewQueue work:^id(SSGitHub *api,NSError **error){return [api peerDirectory:path commit:snapshot[@"commit"] repository:identifier error:error];} done:^(NSArray *files,NSError *error){
            if(preview!=self.previewGeneration)return;
            if(!files){[self showError:error];return;}
            NSMutableDictionary *directory=snapshot.mutableCopy;directory[@"files"]=files;self.browseSnapshots[identifier]=directory;self.selectedFile=nil;
        }];
        return;
    }
    self.selectedFile=path;
    NSString *cacheKey=[NSString stringWithFormat:@"%@|%@|%@",identifier,snapshot[@"commit"],path];
    NSDictionary *cached=[self.previewCache objectForKey:cacheKey];
    if(cached){[self showPeerPreview:cached path:path];[self present];return;}
    [self run:@"读取所选文件…" queue:self.previewQueue work:^id(SSGitHub *api,NSError **error){
        NSDictionary *entry=[self loadFile:file peer:peer api:api error:error];
        if(!entry)return nil;
        if([entry[@"pdf"] boolValue]){
            PDFDocument *document=[[PDFDocument alloc] initWithData:entry[@"data"]];
            if(!document || document.isLocked){if(error)*error=AMPeerError(@"PDF 无法读取或已加密");return nil;}
            return @{@"pdf":document,@"bytes":@([entry[@"data"] length])};
        }
        return @{@"files":@{path:entry},@"paths":@[path],@"bytes":@([entry[@"data"] length])};
    } done:^(NSDictionary *value,NSError *error){
        if(preview!=self.previewGeneration || ![self.selected isEqual:identifier])return;
        if(!value){[self showError:error];return;}
        [self.previewCache setObject:value forKey:cacheKey cost:[value[@"bytes"] unsignedIntegerValue]];
        [self showPeerPreview:value path:path];
        self.status=@"只读预览";
        NSArray *references=AMPreflightImageReferences(value[@"files"][path][@"text"] ?: @"");
        if(!references.count)return;
        // Render the text first. Relative images are loaded independently from the same commit.
        [self run:@"读取文档图片…" queue:self.queue work:^id(SSGitHub *api,NSError **failure){
            NSMutableDictionary *entries=[value[@"files"] mutableCopy];
            NSMutableDictionary *directories=NSMutableDictionary.dictionary;
            NSUInteger cost=[value[@"bytes"] unsignedIntegerValue];
            for(NSDictionary *reference in references){
                NSString *image=AMPreflightResolveImage(path,reference[@"reference"]);
                if(!AMPeerInScope(image,self.scope) || entries[image] || entries.count>=32)continue;
                NSString *folder=image.stringByDeletingLastPathComponent;
                NSArray *files=directories[folder];
                if(!files){files=[api peerDirectory:folder commit:snapshot[@"commit"] repository:identifier error:NULL] ?: @[];directories[folder]=files;}
                for(NSDictionary *asset in files)if([asset[@"path"] isEqual:image]){
                    NSDictionary *data=[self loadFile:asset peer:peer api:api error:NULL];
                    NSUInteger size=[data[@"data"] length];
                    if(data && cost+size<=32*1024*1024){entries[image]=data;cost+=size;}
                    break;
                }
            }
            return @{@"files":entries,@"paths":entries.allKeys,@"bytes":@(cost)};
        } done:^(NSDictionary *enriched,NSError *failure){
            if(preview!=self.previewGeneration || ![self.selected isEqual:identifier] || !enriched)return;
            [self.previewCache setObject:enriched forKey:cacheKey cost:[enriched[@"bytes"] unsignedIntegerValue]];
            [self showPeerPreview:enriched path:path];self.status=@"只读预览";
        }];
    }];
}
- (void)showPeerPreview:(NSDictionary *)value path:(NSString *)path {
    if(value[@"pdf"]){PDFView *view=PDFView.new;view.autoScales=YES;view.document=value[@"pdf"];[self.workspace setPreviewView:view];return;}
    if(!self.documentReader){self.documentReader=AMDocumentView.new;self.documentReader.renderedOnly=YES;}
    [self.documentReader loadSnapshot:value path:path];
    [self.workspace setPreviewView:self.documentReader];
}
#include "AMPeerSourceChecks.inc"
#include "AMPeerScoring.inc"
- (void)action:(NSString *)action identifier:(NSString *)identifier {

    if([action isEqual:@"stop"]){[self stop];return;}if([action isEqual:@"refresh"]){[self reloadScores];[self loadPage:1];if(self.selected)[self browsePeer:self.selected refreshing:YES];return;}
    if([action isEqual:@"more"]){[self loadPage:self.page+1];return;}
    if([action isEqual:@"select"]){[self browsePeer:identifier refreshing:NO];return;}
    if([action isEqual:@"file"]){[self previewFile:identifier];return;}
    if([action isEqual:@"verify"]){for(NSDictionary *peer in self.peers)[self verifyPeer:peer[@"repository"] completion:nil];return;}
    if([action isEqual:@"filter"]){self.filter=identifier.integerValue;[self present];return;}
    if([action isEqual:@"group"]){self.rankingGroup=nil;for(NSDictionary *score in [self savedScores])if([score[@"kind"] hasPrefix:@"llm"]){NSDictionary *group=@{@"rubric":score[@"rubric"],@"model":score[@"model"],@"prompt":score[@"prompt"]};if([AMPeerHash(group) isEqual:identifier]){self.rankingGroup=group;break;}}[self present];return;}
    if([action isEqual:@"github"]){NSDictionary *peer=[self peer:self.selected];NSString *sha=self.snapshots[self.selected ?: @""][@"commit"];if(peer){NSString *tail=self.selectedFile.length && AMPeerSHA(sha) ? [NSString stringWithFormat:@"/blob/%@/%@",sha,self.selectedFile]:@"";NSURLComponents *url=[NSURLComponents componentsWithString:[@"https://github.com/" stringByAppendingString:peer[@"repository"]]];url.path=[url.path stringByAppendingString:tail];[NSWorkspace.sharedWorkspace openURL:url.URL];}return;}
    if(self.grading && [@[@"feedback",@"existing-llm",@"materials",@"remove-materials",@"remove-evaluation",@"rubric",@"grade",@"grade-batch",@"import-score"] containsObject:action])return;
    if([action isEqual:@"feedback"]){self.associatingLLM=NO;[self associateFeedback];}
    if([action isEqual:@"existing-llm"]){self.associatingLLM=YES;[self associateFeedback];}
    if([action isEqual:@"materials"])[self addMaterials];
    if([action isEqual:@"remove-materials"])[self removeMaterials];
    if([action isEqual:@"remove-evaluation"])[self removeEvaluation];
    if([action isEqual:@"rubric"])[self editRubric];
    if([action isEqual:@"grade"] || [action isEqual:@"grade-batch"]){self.batchGrading=[action isEqual:@"grade-batch"];[self grade];}
    if([action isEqual:@"import-score"])[self importScore];
    if([action isEqual:@"score-detail"])[self showScore];
}
@end
