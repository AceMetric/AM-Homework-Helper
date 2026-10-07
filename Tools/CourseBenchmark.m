#import <Foundation/Foundation.h>
#import "../Sources/SSRecognition.h"
#import "../Sources/SSAssignments.h"
#import "../Sources/DDLCore.h"
// Inputs and detailed outputs are explicitly local, never part of a release.
int main(int argc,const char *argv[]){@autoreleasepool{
    if(argc<3)return 2;
    NSData *data=[NSData dataWithContentsOfFile:@(argv[1])];id documents=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;if(![documents isKindOfClass:NSArray.class])return 3;
    NSDictionary *settings=argc>3 ? @{@"mode":@"local",@"endpoint":@"http://localhost:11434",@"model":@(argv[3])} : @{@"mode":@"rules"};
    NSDate *start=NSDate.date;NSMutableArray *assignments=NSMutableArray.array,*materials=NSMutableArray.array,*messages=NSMutableArray.array;NSMutableDictionary *cache=NSMutableDictionary.dictionary;
    for(NSDictionary *document in documents){
        NSCalendar *calendar=NSCalendar.currentCalendar.copy;calendar.timeZone=[NSTimeZone timeZoneWithName:document[@"timeZone"] ?: @"Asia/Shanghai"];
        NSError *error=nil;NSArray *records=SSRecognizeDocument(document[@"text"],document[@"repository"],document[@"path"],document[@"blobSHA"],calendar,settings,cache,&error);
        if(error)[messages addObject:error.localizedDescription];
        for(NSDictionary *record in records){
            NSDictionary *referenced=record;
            id refs=document[@"references"];NSArray *references=[refs isKindOfClass:NSDictionary.class] ? [refs allValues] : ([refs isKindOfClass:NSArray.class] ? refs : @[]);
            for(NSDictionary *reference in references)if([reference isKindOfClass:NSDictionary.class] && [reference[@"line"] isEqual:record[@"line"]]){
                NSISO8601DateFormatter *formatter=NSISO8601DateFormatter.new;NSDate *date=[formatter dateFromString:reference[@"date"]];if(date)referenced=SSApplyDateReference(record,date,reference[@"commit"],calendar);
            }
            if([referenced[@"kind"] isEqual:@"assignment"])[assignments addObject:referenced];else[materials addObject:referenced];
        }
    }
    NSArray *consolidated=SSConsolidateAssignments(assignments),*grouped=SSGroupMaterials(materials);NSMutableDictionary *counts=NSMutableDictionary.dictionary;NSUInteger complete=0,summary=0,requirements=0,exam=0;
    for(NSDictionary *record in consolidated){NSString *course=[record[@"repository"] lastPathComponent];counts[course]=@([counts[course] unsignedIntegerValue]+1);if(record[@"due"] && ![record[@"needsTime"] boolValue])complete++;if([record[@"summary"] length])summary++;if([record[@"submissionRequirements"] length])requirements++;}
    for(NSDictionary *record in grouped)if([record[@"kind"] isEqual:@"exam"])exam++;
    NSDictionary *report=@{@"mode":settings[@"mode"],@"documentCount":@([documents count]),@"assignmentCounts":counts,@"examGroups":@(exam),@"completeDates":@(complete),@"summaries":@(summary),@"submissionRequirements":@(requirements),@"durationSeconds":@(-[start timeIntervalSinceNow]),@"modelErrors":messages,@"assignments":consolidated,@"materials":grouped};
    NSData *output=[NSPropertyListSerialization dataWithPropertyList:report format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];if(![output writeToFile:@(argv[2]) options:NSDataWritingAtomic error:NULL])return 4;
    printf("PASS: benchmark %lu documents, %lu assignments, %lu exam groups; %.2fs\n",(unsigned long)[documents count],(unsigned long)consolidated.count,(unsigned long)exam,-[start timeIntervalSinceNow]);
}return 0;}
