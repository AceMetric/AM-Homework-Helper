#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Returns editable field suggestions. A missing due date must be confirmed in the editor.
NSDictionary<NSString *, id> *DDLFieldsFromAnnouncement(NSString *text, NSDate *now, NSCalendar *calendar);
NSDate * _Nullable DDLPersonalDueDate(NSDate *announcedDue, NSInteger leadDays, NSCalendar *calendar);
NSString * _Nullable DDLOCRTextFromImage(NSImage *image, NSError **error);

NS_ASSUME_NONNULL_END
