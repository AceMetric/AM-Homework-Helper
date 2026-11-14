#import <Foundation/Foundation.h>
#import "../Sources/SSAssignments.h"
static NSUInteger count;
static void Check(BOOL value,NSString *message){count++;if(!value){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
int main(int argc,const char **argv){@autoreleasepool{
    NSString *fixture=argc>1 ? @(argv[1]):@"Tests/Fixtures/requirements-gold.json";
    NSArray *cases=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:fixture] options:0 error:NULL];Check(cases.count>=4,@"gold fixtures loaded");
    for(NSDictionary *test in cases){
        NSArray *items=SSRequirementItems(test[@"text"],@"assignment/README.md",@"teacher-v1");
        NSArray *actual=[items valueForKey:@"text"];
        if(![actual isEqual:test[@"expected"]])fprintf(stderr,"fixture %s expected=%s actual=%s\n",[test[@"name"] UTF8String],[test[@"expected"] description].UTF8String,actual.description.UTF8String);
        Check([actual isEqual:test[@"expected"]],test[@"name"]);
        Check([items isEqual:SSRequirementItems(test[@"text"],@"assignment/README.md",@"teacher-v1")],@"same material has stable items");
        NSMutableSet *ids=NSMutableSet.set;
        for(NSDictionary *item in items){Check([item[@"line"] integerValue]>0 && [item[@"endLine"] integerValue]>=[item[@"line"] integerValue],@"source range retained");Check([item[@"path"] length] && [item[@"version"] length],@"material identity retained");Check(![ids containsObject:item[@"id"]],@"distinct requirements have distinct IDs");[ids addObject:item[@"id"]];}
        if([test[@"name"] hasPrefix:@"conditional"])Check([items[0][@"condition"] length]>0,@"condition stays attached to the requirement");
    }
    NSArray *first=SSRequirementItems(@"提交报告。",@"a.md",@"v1"),*next=SSRequirementItems(@"提交报告。",@"a.md",@"v2");Check(![first[0][@"id"] isEqual:next[0][@"id"]],@"changed teacher version invalidates comparison identity");
    printf("PASS: %lu structured requirement assertions (%s)\n",(unsigned long)count,fixture.UTF8String);
}}
