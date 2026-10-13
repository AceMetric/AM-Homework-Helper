#import "../Sources/DDLUI.h"
#import "../Sources/AMRenderer.h"
#import "../Sources/AMPreflight.h"
#import <WebKit/WebKit.h>
static NSUInteger checks;
static void Check(BOOL value,NSString *message){checks++;if(!value){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static void Wait(BOOL(^ready)(void)){NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:15];while(!ready() && limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];Check(ready(),@"renderer callback completes");}
static NSDictionary *Inspect(NSString *text){NSDictionary *snapshot=@{@"paths":@[@"sample.md"],@"files":@{@"sample.md":@{@"text":text,@"version":AMPreflightHash([text dataUsingEncoding:NSUTF8StringEncoding])}},@"version":@"synthetic"};NSDictionary *report=AMPreflightCheck(snapshot,@"Synthetic requirements",NSMutableDictionary.dictionary,nil);Check([report[@"coverage"] count]>=3 && [report[@"coverage"][1][@"status"] hasPrefix:@"已渲染"],@"actual offline math rendering completes, not just syntax inspection");return report;}
static BOOL Has(NSDictionary *report,NSString *needle){for(NSDictionary *row in report[@"issues"])if([row[@"message"] containsString:needle])return YES;return NO;}
int main(){@autoreleasepool{
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];AMInstallRenderer();
 NSString *valid=@"# Valid math\n\n$\\mathbb{R}\\oplus\\mathfrak{g}$、$L=I\\omega$、$\\mathbf{L}$ 的大小不变。\n\n$`\\frac{1}{2}x^2`$\n\n$$\\begin{aligned}x&=1\\\\y&=2\\end{aligned}$$\n\n```math\n\\sqrt{x+1}\n```\n\nCosts $100 and $200. `\\badcommand $x$`\n\n```python\ntext = '$\\badcommand$'\n```\n\n<img src=\"missing.png\" alt=\"$x$\">\n";
 NSDictionary *report=Inspect(valid);Check([report[@"coverage"][1][@"status"] containsString:@"6 个公式"],@"adjacent formulae all render even when preceding formula has TeX commands");Check(!Has(report,@"公式渲染未完成") && !Has(report,@"未闭合") && !Has(report,@"裸露"),@"complex legal formula, currency, inline code, fences and HTML attributes avoid false format errors");
 Check(Has(Inspect(@"$\\frac{1}{2$\n"),@"公式渲染未完成"),@"actual MathJax catches missing brace");
 Check(Has(Inspect(@"$\\unsupportedcommand{x}$\n"),@"公式渲染未完成"),@"unknown command classified as compatibility warning");
 Check(Has(Inspect(@"$$\nx+1\n"),@"块公式未闭合"),@"unclosed block formula detected");
 Check(Has(Inspect(@"$x+1\n"),@"未闭合"),@"plain algebra with a missing delimiter is not silently skipped");
 Check(!Has(Inspect(@"Files: ./assets/$x+1.md and C:\\frac\\data.\nCosts $100 and $200.\n"),@"未闭合"),@"paths and currency do not become incomplete formula warnings");
 Check(Has(Inspect(@"$\\mathbf{x}\n"),@"未闭合"),@"unclosed inline formula detected");
 Check(Has(Inspect(@"A literal \\mathbf{x} outside math.\n"),@"裸露"),@"escaped or missing math delimiter leaves visible compatibility warning");
 AMDocumentView *view=[[AMDocumentView alloc] initWithFrame:NSMakeRect(0,0,700,480)];NSWindow *host=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,700,480) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];host.releasedWhenClosed=NO;host.contentView=view;
 NSString *attack=@"# Preview\n<script>window.materialExecuted=1</script><img src=\"https://example.invalid/x\" onerror=\"window.materialExecuted=1\"><a href=\"file:///private/etc/passwd\">link</a>\n\n$x^2$\n";
 [view loadSnapshot:@{@"files":@{@"test.md":@{@"text":attack}}} path:@"test.md"];WKWebView *web=[view valueForKey:@"web"];__block BOOL ready=NO;
 Wait(^BOOL{if(!ready){[web evaluateJavaScript:@"!!document.querySelector('mjx-container')" completionHandler:^(id result,NSError *error){ready=[result boolValue];}];}return ready;});
 __block NSDictionary *state=nil;[web evaluateJavaScript:@"({executed:!!window.materialExecuted,external:!!document.querySelector('#content img[src^=https]'),link:!!document.querySelector('#content a[href]'),formula:!!document.querySelector('mjx-container')})" completionHandler:^(id result,NSError *error){state=result;}];Wait(^BOOL{return state!=nil;});Check(![state[@"executed"] boolValue] && ![state[@"external"] boolValue] && ![state[@"link"] boolValue] && [state[@"formula"] boolValue],@"material scripts, event handlers, remote images and file links cannot execute or navigate");
 [view locateLine:0];[view showSource:YES];Check(![[view valueForKey:@"sourceScroll"] isHidden],@"source toggle and zero-line navigation are safe");
 __block BOOL dark=NO;host.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];[web evaluateJavaScript:@"document.documentElement.dataset.appearance" completionHandler:^(id result,NSError *error){dark=[result isEqual:@"dark"];}];Wait(^BOOL{return dark;});Check([[[view valueForKey:@"sourceText"] string] isEqual:attack],@"theme updates web and source without rebuilding or losing text");
 [host close];printf("PASS: %lu offline renderer and security assertions\n",(unsigned long)checks);
}return 0;}
