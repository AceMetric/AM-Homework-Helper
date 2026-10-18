#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL valid,NSString *message){checks++;if(!valid){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static void Case(NSString *name,NSDictionary *manifest,NSDictionary *blobs,BOOL unexpected) {
    NSURL *root=[NSURL fileURLWithPath:[NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"] stringByAppendingPathComponent:name]];
    NSFileManager *fm=NSFileManager.defaultManager;NSURL *input=[root URLByAppendingPathComponent:@"input"],*resources=[root URLByAppendingPathComponent:@"resources"],*workspace=[root URLByAppendingPathComponent:@"workspace"];
    for(NSURL *dir in @[input,resources,workspace])[fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSData *json=manifest ? [NSJSONSerialization dataWithJSONObject:manifest options:0 error:nil]:[@"not JSON" dataUsingEncoding:NSUTF8StringEncoding];[json writeToURL:[input URLByAppendingPathComponent:@"manifest.json"] atomically:YES];
    for(NSString *key in blobs){NSURL *file=[input URLByAppendingPathComponent:[@"blobs/" stringByAppendingString:key]];[fm createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];[blobs[key] writeToURL:file atomically:YES];}
    if(unexpected)[@"x" writeToURL:[input URLByAppendingPathComponent:@"unexpected.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray *members=[NSMutableArray arrayWithObject:@"manifest.json"];for(NSString *key in blobs)[members addObject:[@"blobs/" stringByAppendingString:key]];if(unexpected)[members addObject:@"unexpected.txt"];
    NSTask *zip=NSTask.new;zip.executableURL=[NSURL fileURLWithPath:@"/usr/bin/zip"];zip.currentDirectoryURL=input;zip.arguments=[@[@"-X",@"-q",[resources URLByAppendingPathComponent:@"ReminderIdentities.zip"].path] arrayByAddingObjectsFromArray:members];Check([zip launchAndReturnError:nil],@"fixture archive launches");[zip waitUntilExit];Check(zip.terminationStatus==0,@"fixture archive completes");
    NSError *error=nil;NSArray *result=AMClearHistoricalReminderSources(resources,workspace,nil,^BOOL{return NO;},nil,&error);
    NSDictionary *reasons=@{@"unexpected-member":@"路径无效",@"invalid-json":@"身份无效",@"foreign-identity":@"身份无效",@"malformed-host":@"应用清单无效",@"escaping-path":@"文件路径无效",@"invalid-blob-path":@"文件路径无效",@"modified-blob":@"校验失败",@"escaping-link":@"链接路径无效",@"duplicate-hosts":@"清单无效",@"unsigned-host":@"签名无法验证"};
    Check(!result && [error.localizedDescription containsString:reasons[name]],[name stringByAppendingFormat:@" rejects at the intended boundary: %@",error.localizedDescription]);
}
int main(void){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"].length>0,@"tests use isolated storage");
    NSDictionary *base=@{@"format":@1,@"bundleID":@"io.github.acemetric.sshomeworkmanager",@"hosts":@[]};
    Case(@"unexpected-member",base,@{},YES);Case(@"invalid-json",nil,@{},NO);
    Case(@"foreign-identity",@{@"format":@1,@"bundleID":@"example.invalid.foreign",@"hosts":@[]},@{},NO);
    Case(@"malformed-host",@{@"format":@1,@"bundleID":base[@"bundleID"],@"hosts":@[@"bad"]},@{},NO);
    NSData *data=[@"synthetic sealed file" dataUsingEncoding:NSUTF8StringEncoding];NSString *sha=AMPreflightHash(data);
    NSDictionary *(^host)(NSArray *)=^NSDictionary *(NSArray *files){return @{@"version":@"1.0",@"executable":@"Probe",@"files":files};};
    NSDictionary *(^document)(NSArray *)=^NSDictionary *(NSArray *hosts){return @{@"format":@1,@"bundleID":base[@"bundleID"],@"hosts":hosts};};
    NSDictionary *row=@{@"path":@"Contents/Info.plist",@"blob":sha,@"mode":@0644,@"link":@NO};
    NSMutableDictionary *escape=row.mutableCopy;escape[@"path"]=@"Contents/../../escape";
    Case(@"escaping-path",document(@[host(@[escape])]),@{sha:data},NO);
    NSMutableDictionary *invalid=row.mutableCopy;invalid[@"blob"]=@"../../not-a-hash";
    Case(@"invalid-blob-path",document(@[host(@[invalid])]),@{},NO);
    Case(@"modified-blob",document(@[host(@[row])]),@{sha:[@"changed" dataUsingEncoding:NSUTF8StringEncoding]},NO);
    NSData *link=[@"../../../escape" dataUsingEncoding:NSUTF8StringEncoding];NSString *linkSHA=AMPreflightHash(link);NSDictionary *linkRow=@{@"path":@"Contents/link",@"blob":linkSHA,@"mode":@0777,@"link":@YES};
    Case(@"escaping-link",document(@[host(@[linkRow])]),@{linkSHA:link},NO);
    Case(@"duplicate-hosts",document(@[host(@[]),host(@[])]),@{},NO);
    NSDictionary *info=@{@"CFBundleIdentifier":base[@"bundleID"],@"CFBundleShortVersionString":@"1.0",@"CFBundleExecutable":@"Probe",@"CFBundlePackageType":@"APPL"};
    NSData *infoData=[NSPropertyListSerialization dataWithPropertyList:info format:NSPropertyListXMLFormat_v1_0 options:0 error:nil],*script=[@"#!/bin/sh\nexit 0\n" dataUsingEncoding:NSUTF8StringEncoding];NSString *infoSHA=AMPreflightHash(infoData),*scriptSHA=AMPreflightHash(script);
    NSDictionary *infoRow=@{@"path":@"Contents/Info.plist",@"blob":infoSHA,@"mode":@0644,@"link":@NO},*scriptRow=@{@"path":@"Contents/MacOS/Probe",@"blob":scriptSHA,@"mode":@0755,@"link":@NO};
    Case(@"unsigned-host",document(@[host(@[infoRow,scriptRow])]),@{infoSHA:infoData,scriptSHA:script},NO);
    Check(!AMReminderRelativePath(@"/tmp/escape") && !AMReminderRelativePath(@"Contents/../escape"),@"absolute and traversal paths rejected");
    printf("PASS: %lu reminder migration provenance and failure assertions; no production notifications accessed\n",(unsigned long)checks);
}return 0;}
