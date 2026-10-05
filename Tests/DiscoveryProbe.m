// Local corpus runner. Inputs and reports belong in ignored build/qa, never in source control.
#import <Foundation/Foundation.h>
#import "../Sources/SSAssignments.h"
int main(int argc, char **argv) { @autoreleasepool {
    if (argc != 3) return 2;
    NSArray *documents = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:nil];
    if (![documents isKindOfClass:NSArray.class]) return 2;
    NSMutableArray *records = NSMutableArray.array;
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; calendar.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    for (NSDictionary *document in documents) {
        NSArray *found = SSDiscoveriesFromDocument(document[@"text"], document[@"repository"], document[@"path"], document[@"blobSHA"], NSDate.date, calendar);
        [records addObjectsFromArray:found];
    }
    NSArray *assignments = SSConsolidateAssignments(records);
    NSDictionary *report = @{@"records":records, @"assignments":assignments, @"materials":SSGroupMaterials(records)};
    if (![report writeToFile:@(argv[2]) atomically:YES]) return 1;
    printf("PASS: corpus parsed: %lu assignments, %lu material groups\n", (unsigned long)assignments.count, (unsigned long)[report[@"materials"] count]);
} return 0; }
