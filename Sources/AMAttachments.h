#import <Cocoa/Cocoa.h>
#import "SSSecurity.h"

NS_INLINE NSError *AMAttachmentError(NSString *message){return [NSError errorWithDomain:@"AMAttachments" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];}
NS_INLINE NSURL *AMAttachmentDestination(NSURL *root,NSString *scope,NSString *name,NSError **error){
    NSURL *canonical=root.URLByResolvingSymlinksInPath.URLByStandardizingPath;NSString *destinationScope=scope ?: @"";
    if(!root.isFileURL || !destinationScope.length || [destinationScope hasPrefix:@"/"] || [destinationScope.pathComponents containsObject:@".."] || !name.length || ![name isEqual:name.lastPathComponent] || SSSensitivePath(name)){if(error)*error=AMAttachmentError(@"请选择明确的作业目录及普通文件名");return nil;}
    NSURL *folder=[canonical URLByAppendingPathComponent:destinationScope isDirectory:YES];NSString *prefix=[canonical.path stringByAppendingString:@"/"];if(![folder.URLByResolvingSymlinksInPath.path hasPrefix:prefix] || ![folder.path isEqual:folder.URLByResolvingSymlinksInPath.path]){if(error)*error=AMAttachmentError(@"目标不在已确认的作业目录内");return nil;}
    BOOL directory=NO;if(![NSFileManager.defaultManager fileExistsAtPath:folder.path isDirectory:&directory] || !directory){if(error)*error=AMAttachmentError(@"作业目录不存在，请重新关联");return nil;}
    NSURL *target=[folder URLByAppendingPathComponent:name];if(![target.path isEqual:target.URLByResolvingSymlinksInPath.path] || [NSFileManager.defaultManager fileExistsAtPath:target.path]){if(error)*error=AMAttachmentError(@"目标文件已存在，请改名");return nil;}return target;
}
@interface AMAttachmentDropView : Surface
@property(copy) BOOL(^importPasteboard)(NSPasteboard *);
@end
@implementation AMAttachmentDropView
- (instancetype)initWithFrame:(NSRect)frame {if((self=[super initWithFrame:frame]))[self registerForDraggedTypes:@[NSPasteboardTypeFileURL,NSPasteboardTypePNG,NSPasteboardTypeTIFF]];return self;}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {return self.importPasteboard ? NSDragOperationCopy:NSDragOperationNone;}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {return self.importPasteboard ? self.importPasteboard(sender.draggingPasteboard):NO;}
@end
