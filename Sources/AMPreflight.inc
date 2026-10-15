static NSDictionary *(^PFRenderer)(NSString *,NSString *);
void AMPreflightSetRenderer(NSDictionary *(^renderer)(NSString *,NSString *)){PFRenderer=[renderer copy];}
#import "AMPreflight.h"
#import <ImageIO/ImageIO.h>
#include <math.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>
#import <dirent.h>
NSString *AMPreflightExcludedReason(NSString *path){
    if(SSSensitivePath(path))return @"敏感文件已排除";
    NSSet *generated=[NSSet setWithArray:@[@"node_modules",@"vendor",@"venv",@"__pycache__",@"build",@"build.noindex",@"dist",@"target",@"DerivedData"]];
    for(NSString *part in path.pathComponents){if([part hasPrefix:@"."] && ![part isEqual:@"."] && ![part isEqual:@".."])return @"隐藏配置或元数据已排除";if([generated containsObject:part])return @"依赖、缓存或构建目录已排除";}
    return nil;
}
NSString *AMPreflightFileStamp(NSURL *folder,NSString *path){
    if(!path.length || [path hasPrefix:@"/"] || [path.pathComponents containsObject:@".."])return @"unsafe";
    int fd=open(folder.path.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);if(fd<0)return @"unsafe";
    NSArray *parts=path.pathComponents;for(NSUInteger i=0;i+1<parts.count;i++){int next=openat(fd,[parts[i] fileSystemRepresentation],O_RDONLY|O_DIRECTORY|O_NOFOLLOW);close(fd);fd=next;if(fd<0)return @"unsafe";}
    struct stat st;int result=fstatat(fd,[parts.lastObject fileSystemRepresentation],&st,AT_SYMLINK_NOFOLLOW);close(fd);if(result<0)return @"absent";if(!S_ISREG(st.st_mode))return @"unsafe";
    return [NSString stringWithFormat:@"%llu:%llu:%lld:%lld:%ld:%lld:%ld",(unsigned long long)st.st_dev,(unsigned long long)st.st_ino,(long long)st.st_size,(long long)st.st_mtimespec.tv_sec,st.st_mtimespec.tv_nsec,(long long)st.st_ctimespec.tv_sec,st.st_ctimespec.tv_nsec];
}
NSArray *AMPreflightListSelectedFiles(NSURL *folder,NSArray *paths){
    NSMutableArray *rows=NSMutableArray.array;
    NSSet *images=[NSSet setWithArray:@[@"png",@"jpg",@"jpeg",@"heic",@"tiff",@"tif",@"gif",@"bmp",@"webp"]];
    NSSet *text=[NSSet setWithArray:@[@"md",@"markdown",@"mdx",@"txt",@"text",@"rst",@"tex",@"csv",@"json",@"yaml",@"yml",@"ipynb",@"py",@"c",@"h",@"cpp",@"cc",@"hpp",@"java",@"js",@"ts",@"jsx",@"tsx",@"swift",@"m",@"mm",@"rs",@"go",@"r",@"jl",@"sql",@"sh"]];
    for(NSString *path in [NSOrderedSet orderedSetWithArray:paths]){
        NSString *stamp=AMPreflightFileStamp(folder,path),*ext=path.pathExtension.lowercaseString,*reason=nil;NSArray *fields=[stamp componentsSeparatedByString:@":"];unsigned long long bytes=fields.count==7 ? [fields[2] longLongValue]:0;
        if(AMPreflightExcludedReason(path))reason=AMPreflightExcludedReason(path);else if(fields.count!=7)reason=@"文件无法读取或包含符号链接";else if(bytes>5*1024*1024)reason=@"超过每文件5 MB限制";else if(![images containsObject:ext] && ![text containsObject:ext])reason=@"不支持的文件类型，未检查";
        [rows addObject:@{@"path":path,@"image":@([images containsObject:ext]),@"bytes":@(bytes),@"selectable":@(!reason),@"reason":reason ?: @""}];
    }
    return rows;
}
// Enumerate names and metadata only, using directory descriptors so a replaced
// directory or symlink cannot redirect traversal outside the chosen root.
NSDictionary *AMPreflightListFolder(NSURL *folder,BOOL(^cancelled)(void),void(^progress)(NSUInteger),NSError **error){
    int root=open(folder.path.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    if(root<0){if(error)*error=RError(@"无法打开作业文件夹，请重新选择可读取的本机目录。");return nil;}
    NSMutableArray *rows=NSMutableArray.array;__block NSUInteger count=0;__block NSString *failure=nil;
    NSSet *generated=[NSSet setWithArray:@[@"node_modules",@"vendor",@"venv",@"__pycache__",@"build",@"build.noindex",@"dist",@"target",@"DerivedData"]];
    NSSet *images=[NSSet setWithArray:@[@"png",@"jpg",@"jpeg",@"heic",@"tiff",@"tif",@"gif",@"bmp",@"webp"]];
    NSSet *texts=[NSSet setWithArray:@[@"md",@"markdown",@"mdx",@"txt",@"text",@"rst",@"tex",@"csv",@"json",@"yaml",@"yml",@"ipynb",@"py",@"c",@"h",@"cpp",@"cc",@"hpp",@"java",@"js",@"ts",@"jsx",@"tsx",@"swift",@"m",@"mm",@"rs",@"go",@"r",@"jl",@"sql",@"sh"]];
    __block void(^ __weak recurse)(int,NSString *,NSUInteger);
    void(^walk)(int,NSString *,NSUInteger);
    walk=^(int descriptor,NSString *prefix,NSUInteger depth){
        DIR *dir=fdopendir(descriptor);if(!dir){close(descriptor);failure=@"文件夹无法完整读取，请检查权限。";return;}
        struct dirent *item;
        errno=0;
        while(!failure && (item=readdir(dir))){
            NSString *name=[NSFileManager.defaultManager stringWithFileSystemRepresentation:item->d_name length:strlen(item->d_name)];
            if([name isEqual:@"."] || [name isEqual:@".."])continue;
            if(cancelled && cancelled()){failure=@"整理已取消，未开始检查。";break;}
            if(++count>10000){failure=@"目录超过10,000项，请选择更小的作业文件夹。";break;}
            if(progress && count%32==0)progress(count);
            NSString *path=prefix.length ? [prefix stringByAppendingPathComponent:name]:name,*reason=nil;
            struct stat st;BOOL ok=fstatat(dirfd(dir),item->d_name,&st,AT_SYMLINK_NOFOLLOW)==0;
            if(!ok)reason=@"无法读取文件信息";
            else if(S_ISLNK(st.st_mode))reason=@"符号链接未读取";
            else if([name hasPrefix:@"."] || SSSensitivePath(path))reason=@"隐藏配置、元数据或敏感文件已排除";
            else if(S_ISDIR(st.st_mode) && [generated containsObject:name])reason=@"依赖、缓存或构建目录已排除";
            else if(S_ISDIR(st.st_mode)){
                if(depth>=64){failure=@"目录嵌套过深，请选择更小的作业文件夹。";break;}
                int child=openat(dirfd(dir),item->d_name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
                if(child<0)reason=@"目录无法读取或已变化";else{recurse(child,path,depth+1);errno=0;continue;}
            }else if(!S_ISREG(st.st_mode))reason=@"非普通文件未读取";
            else if(st.st_size>5*1024*1024)reason=@"超过每文件5 MB限制";
            NSString *ext=path.pathExtension.lowercaseString;BOOL image=[images containsObject:ext];
            if(!reason && !image && ![texts containsObject:ext])reason=@"不支持的文件类型，未检查";
            [rows addObject:@{@"path":path,@"image":@(image),@"bytes":@(ok ? MAX(0,st.st_size):0),@"selectable":@(!reason),@"reason":reason ?: @""}];
            errno=0;
        }
        if(errno && !failure)failure=@"目录读取中断，请重试；未使用不完整清单。";
        closedir(dir);
    };
    recurse=walk;walk(root,@"",0);
    if(failure){if(error)*error=RError(failure);return nil;}
    if(progress)progress(count);
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"path"] localizedStandardCompare:b[@"path"]];}];
    return @{@"files":rows,@"enumerated":@(count)};
}
NSString *AMPreflightHash(NSData *data){unsigned char d[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,d);NSMutableString *s=NSMutableString.string;for(NSUInteger i=0;i<sizeof(d);i++)[s appendFormat:@"%02x",d[i]];return s;}
static NSArray *PFMatches(NSString *s,NSString *pattern){return [[NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL] matchesInString:s options:0 range:NSMakeRange(0,s.length)] ?: @[];}
static NSString *PFGroup(NSString *s,NSTextCheckingResult *m,NSUInteger n){NSRange r=[m rangeAtIndex:n];return r.location==NSNotFound ? @"" : [s substringWithRange:r];}
static NSString *PFVisible(NSString *text){
    NSMutableArray *lines=NSMutableArray.array;NSString *fence=nil;NSUInteger count=0;
    for(NSString *line in [text componentsSeparatedByString:@"\n"]){NSString *t=RTrim(line);NSArray *f=PFMatches(t,@"^(`{3,}|~{3,})");if(f.count){NSString *mark=PFGroup(t,f[0],1);if(!fence){fence=[mark substringToIndex:1];count=mark.length;}else if([mark hasPrefix:fence] && mark.length>=count && !RTrim([t substringFromIndex:mark.length]).length)fence=nil;[lines addObject:[@"" stringByPaddingToLength:line.length withString:@" " startingAtIndex:0]];continue;}[lines addObject:fence ? [@"" stringByPaddingToLength:line.length withString:@" " startingAtIndex:0] : line];}
    NSMutableString *s=[[lines componentsJoinedByString:@"\n"] mutableCopy];
    // Mask inline code and comments without moving line anchors.
    for(NSString *pattern in @[@"(`+)[^`\\n]*\\1",@"<!--[\\s\\S]*?-->"]){NSArray *matches=PFMatches(s,pattern);for(NSTextCheckingResult *m in matches.reverseObjectEnumerator){NSString *part=[s substringWithRange:m.range];NSMutableString *mask=NSMutableString.string;for(NSUInteger i=0;i<part.length;i++)[mask appendString:[part characterAtIndex:i]=='\n' ? @"\n":@" "];[s replaceCharactersInRange:m.range withString:mask];}}
    return s;
}
// Keep UTF-16 offsets intact so a repeated word points to its actual line.
NSString *AMPreflightSpellingProse(NSString *text){
    NSMutableString *prose=PFVisible(text).mutableCopy;
    for(NSString *pattern in @[@"<[^>]*>",@"\\$\\$[\\s\\S]*?\\$\\$",@"\\$[^$\\n]*\\$",@"\\\\\\([\\s\\S]*?\\\\\\)",@"\\\\\\[[\\s\\S]*?\\\\\\]",@"\\\\[A-Za-z]+(?:\\{[^}]*\\})?",@"!?\\[[^]\\n]*\\]\\([^\\n]*?\\)",@"(?m)^\\s*\\[[^]\\n]+\\]:[^\\n]*",@"https?://[^\\s]+",@"[A-Za-z0-9_.-]+(?:[/\\\\][^\\s<>]*)+",@"\\b[^\\s]*[_.][A-Za-z0-9_.-]+\\b"]){
        for(NSTextCheckingResult *m in PFMatches(prose,pattern)){
            NSMutableString *mask=[[prose substringWithRange:m.range] mutableCopy];
            for(NSUInteger i=0;i<mask.length;i++)if([mask characterAtIndex:i]!='\n')[mask replaceCharactersInRange:NSMakeRange(i,1) withString:@" "];
            [prose replaceCharactersInRange:m.range withString:mask];
        }
    }
    return prose;
}
static BOOL PFSpellingWord(NSString *word){
    if(!PFMatches(word,@"^[a-z]{3,}$").count)return NO;
    // Acronyms, mixed-case identifiers and SI symbols are not prose misspellings.
    if(![word isEqual:word.lowercaseString] && ![word isEqual:word.lowercaseString.capitalizedString])return NO;
    return ![@[@"mol",@"rad",@"mrad",@"kpa",@"mpa",@"ghz",@"mhz",@"khz",@"kev",@"mev",@"kwh"] containsObject:word.lowercaseString];
}
NSArray *AMPreflightImageReferences(NSString *text){
    NSString *visible=PFVisible(text);NSMutableDictionary *definitions=NSMutableDictionary.dictionary;
    for(NSTextCheckingResult *m in PFMatches(visible,@"(?m)^ {0,3}\\[([^]\\n]+)\\]:\\s*(?:<([^>\\n]+)>|([^\\n]+))")){NSString *target=RTrim(PFGroup(visible,m,2).length ? PFGroup(visible,m,2):PFGroup(visible,m,3));NSArray *title=PFMatches(target,@"\\s+[\"'].*[\"']\\s*$");if(title.count)target=RTrim([target substringToIndex:[title[0] range].location]);definitions[[RTrim(PFGroup(visible,m,1)) lowercaseString]]=target;}
    NSMutableArray *refs=NSMutableArray.array;
    for(NSString *pattern in @[@"!\\[([^]\\n]*)\\]\\((?:<([^>\\n]+)>|((?:[^()\\n]|\\([^()\\n]*\\))*))\\)",@"!\\[([^]\\n]*)\\](?:\\[([^]\\n]*)\\])?",@"<img\\b[^>]*?\\bsrc\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))[^>]*>"]){
        NSUInteger kind=[pattern hasPrefix:@"<"] ? 2 : ([pattern containsString:@"\\("] ? 0:1);
        for(NSTextCheckingResult *m in PFMatches(visible,pattern)){
            if(m.range.location>0 && [visible characterAtIndex:m.range.location-1]=='\\')continue;
            if(kind==1 && NSMaxRange(m.range)<visible.length && [visible characterAtIndex:NSMaxRange(m.range)]=='(')continue;
            NSString *ref=nil;
            if(kind==0){ref=PFGroup(visible,m,2);if(!ref.length)ref=PFGroup(visible,m,3);NSArray *title=PFMatches(ref,@"\\s+[\"'].*[\"']\\s*$");if(title.count)ref=[ref substringToIndex:[title[0] range].location];}
            else if(kind==1){NSString *label=PFGroup(visible,m,2);if(!label.length)label=PFGroup(visible,m,1);ref=definitions[RTrim(label).lowercaseString] ?: @"";}
            else {ref=PFGroup(visible,m,1);if(!ref.length)ref=PFGroup(visible,m,2);if(!ref.length)ref=PFGroup(visible,m,3);ref=[[[ref stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"] stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""] stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];}
            NSUInteger line=[[visible substringToIndex:m.range.location] componentsSeparatedByString:@"\n"].count;
            [refs addObject:@{@"reference":RTrim(ref ?: @""),@"line":@(line),@"offset":@(m.range.location)}];
        }
    }
    return [refs sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"offset"] compare:b[@"offset"]];}];
}
NSString *AMPreflightResolveImage(NSString *document,NSString *reference){
    NSString *ref=[reference stringByRemovingPercentEncoding];if(!ref || !ref.length || [ref hasPrefix:@"/"] || [ref containsString:@":"] || [ref containsString:@"\\"] || [ref rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return nil;
    ref=[[ref componentsSeparatedByString:@"#"] firstObject];ref=[[ref componentsSeparatedByString:@"?"] firstObject];
    NSMutableArray *parts=[[document.stringByDeletingLastPathComponent componentsSeparatedByString:@"/"] mutableCopy];[parts removeObject:@""];
    for(NSString *part in [ref componentsSeparatedByString:@"/"]){if([part isEqual:@".."]){if(!parts.count)return nil;[parts removeLastObject];}else if(part.length && ![part isEqual:@"."])[parts addObject:part];}
    return parts.count ? [parts componentsJoinedByString:@"/"]:nil;
}
static NSDictionary *PFIssue(NSString *category,NSString *severity,NSString *path,NSNumber *line,NSString *message,NSString *evidence,NSString *suggestion){return @{@"id":AMPreflightHash([[NSString stringWithFormat:@"%@|%@|%@|%@",path,line,category,message] dataUsingEncoding:NSUTF8StringEncoding]),@"category":category,@"severity":severity,@"path":path,@"line":line ?: @1,@"message":message,@"evidence":evidence ?: @"",@"suggestion":suggestion ?: @"",@"provider":@"local"};}
static NSData *PFImage(NSData *data){
    if(!data.length)return nil;CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);if(!source)return nil;
    NSDictionary *props=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));double w=[props[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue],h=[props[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
    if(w<=0 || h<=0 || w*h>50000000){CFRelease(source);return nil;}
    NSDictionary *options=@{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@((NSUInteger)MAX(w,h))};
    CGImageRef image=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)options);CFRelease(source);if(!image)return nil;
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithCGImage:image];CGImageRelease(image);return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}
// Parse syntax with an Apple-installed interpreter only; never import or run submitted code.
static NSDictionary *PFPython(NSString *source){
    NSString *executable=@"/Library/Developer/CommandLineTools/usr/bin/python3";
    if(![NSFileManager.defaultManager isExecutableFileAtPath:executable] || source.length>1000000)return @{@"status":@"未检查：无可信 Python 解析器或源码过大"};
    NSTask *task=NSTask.new;task.executableURL=[NSURL fileURLWithPath:executable];task.arguments=@[@"-I",@"-S",@"-B",@"-c",@"import ast,json,sys\ntry: ast.parse(sys.stdin.read()); print('{}')\nexcept SyntaxError as e: print(json.dumps({'line':e.lineno or 1,'message':e.msg}))"];task.environment=@{@"PATH":@"/usr/bin:/bin",@"LC_ALL":@"C"};task.currentDirectoryURL=[NSURL fileURLWithPath:@"/private/tmp"];
    NSPipe *input=NSPipe.pipe,*output=NSPipe.pipe;task.standardInput=input;task.standardOutput=output;task.standardError=NSFileHandle.fileHandleWithNullDevice;
    if(![task launchAndReturnError:NULL])return @{@"status":@"未检查：Python 解析器不可用"};
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{if(task.running)[task terminate];});
    @try{[input.fileHandleForWriting writeData:[source dataUsingEncoding:NSUTF8StringEncoding]];[input.fileHandleForWriting closeFile];}@catch(NSException *exception){[task terminate];return @{@"status":@"未检查：Python 语法读取失败"};}
    NSData *data=[output.fileHandleForReading readDataToEndOfFile];[task waitUntilExit];NSDictionary *result=data.length<8192 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
    if(task.terminationStatus!=0 || ![result isKindOfClass:NSDictionary.class])return @{@"status":@"未检查：Python 语法解析未完成"};
    return @{@"status":@"已检查：Python 语法（未执行代码）",@"syntax":result};
}
NSDictionary *AMPreflightCheck(NSDictionary *snapshot,NSString *requirements,NSMutableDictionary *cache,BOOL (^cancelled)(void)){return AMPreflightCheckWithProgress(snapshot,requirements,cache,cancelled,nil);}
NSDictionary *AMPreflightCheckWithProgress(NSDictionary *snapshot,NSString *requirements,NSMutableDictionary *cache,BOOL (^cancelled)(void),void (^progress)(NSUInteger,NSUInteger)){
    NSUInteger processed=0,total=[snapshot[@"paths"] count];
    NSMutableArray *issues=NSMutableArray.array,*coverage=NSMutableArray.array,*images=NSMutableArray.array;NSDictionary *files=snapshot[@"files"];
    for(NSString *path in snapshot[@"paths"]){if(progress)progress(processed++,total);if(cancelled && cancelled())return @{@"cancelled":@YES};NSDictionary *entry=files[path];if([entry[@"deleted"] boolValue])continue;
        NSString *key=[NSString stringWithFormat:@"preflight-v3-renderer4|%@|%@",path,entry[@"version"] ?: @""];NSDictionary *cached=cache[key];
        if(!cached){NSMutableArray *found=NSMutableArray.array;NSDictionary *math=nil;NSString *text=entry[@"text"],*ext=path.pathExtension.lowercaseString,*status=@"未检查：不支持的文件类型";
            if(entry[@"problem"])[found addObject:PFIssue(@"format",@"error",path,@1,entry[@"problem"],@"",@"检查文件格式与大小后重新检查。")];
            else if(text){status=@"已检查：文本结构与明显未完成项";NSArray *lines=[text componentsSeparatedByString:@"\n"];BOOL markdown=[@[@"md",@"markdown",@"mdx"] containsObject:ext];NSString *visible=markdown ? PFVisible(text):text;NSArray *viewLines=[visible componentsSeparatedByString:@"\n"];
                if(!RTrim(text).length)[found addObject:PFIssue(@"incomplete",@"warning",path,@1,@"文件为空",@"",@"确认是否遗漏作答。")];
                for(NSUInteger i=0;i<lines.count;i++){NSString *line=lines[i],*v=viewLines[i];if(PFMatches(line,@"^(?:<{7} |={7}$|>{7} )").count)[found addObject:PFIssue(@"format",@"error",path,@(i+1),@"发现合并冲突标记",line,@"先解决合并冲突。")];
                    if(PFMatches(markdown ? v:line,@"(?i)\\b(?:TODO|FIXME|TBD)\\b|待完成|此处填写|(?m)^\\s*[-*+]\\s+\\[ \\]").count)[found addObject:PFIssue(@"incomplete",@"warning",path,@(i+1),@"疑似未完成内容",line,@"核对这部分是否需要作答。")];}
                if(markdown){NSUInteger fences=0;NSString *mark=nil;NSUInteger length=0;for(NSString *line in lines){NSArray *m=PFMatches(RTrim(line),@"^(`{3,}|~{3,})");if(!m.count)continue;NSString *token=PFGroup(RTrim(line),m[0],1);if(!mark){mark=[token substringToIndex:1];length=token.length;fences++;}else if([token hasPrefix:mark] && token.length>=length && !RTrim([RTrim(line) substringFromIndex:token.length]).length){mark=nil;fences--;}}if(fences)[found addObject:PFIssue(@"format",@"warning",path,@1,@"代码围栏可能未闭合",@"",@"核对 Markdown 预览；这是结构提示。")];
                    math=PFRenderer ? PFRenderer(text,path):@{@"completed":@NO,@"issues":@[]};
                    for(NSDictionary *issue in math[@"issues"]){NSUInteger line=MAX(1,[issue[@"line"] unsignedIntegerValue]);[found addObject:PFIssue(@"format",issue[@"severity"] ?: @"warning",path,@(line),issue[@"message"] ?: @"公式兼容性提示",issue[@"evidence"] ?: @"",issue[@"suggestion"] ?: @"核对源码与渲染结果。")];}
                    // Check natural language only. Formulae, code and URLs are excluded.
                    NSMutableString *prose=AMPreflightSpellingProse(text).mutableCopy;
                    if(prose.length>100000)prose=[[prose substringToIndex:100000] mutableCopy];
                    NSArray *words=PFMatches(prose,@"\\b[A-Za-z]{3,}\\b");if(words.count){__block NSArray *spelling=nil;void (^check)(void)=^{NSSpellChecker *checker=NSSpellChecker.sharedSpellChecker;NSMutableArray *matches=NSMutableArray.array;NSUInteger position=0;while(position<prose.length && matches.count<200){NSRange r=[checker checkSpellingOfString:prose startingAt:position language:@"en_US" wrap:NO inSpellDocumentWithTag:0 wordCount:NULL];if(r.location==NSNotFound || !r.length)break;[matches addObject:[NSTextCheckingResult spellCheckingResultWithRange:r]];position=NSMaxRange(r);}spelling=matches;};if(NSThread.isMainThread)check();else dispatch_sync(dispatch_get_main_queue(),check);NSUInteger count=0;for(NSTextCheckingResult *m in spelling){if(m.range.location==NSNotFound || NSMaxRange(m.range)>prose.length)continue;NSString *word=[prose substringWithRange:m.range];if(!PFSpellingWord(word))continue;NSRange loc=m.range;NSUInteger line=[[text substringToIndex:loc.location] componentsSeparatedByString:@"\n"].count;[found addObject:PFIssue(@"spelling",@"info",path,@(line),@"英文拼写建议（非语法错误）",word,@"仅供参考；课程术语与专有名词可忽略。")];if(++count>=20)break;}}
                }
                if([ext isEqual:@"py"]){NSDictionary *parse=PFPython(text);status=parse[@"status"];if(parse[@"syntax"][@"message"])[found addObject:PFIssue(@"format",@"warning",path,parse[@"syntax"][@"line"],@"Python 语法可能有误",parse[@"syntax"][@"message"],@"核对目标 Python 版本和语法；未执行代码。")];}
                if([ext isEqual:@"ipynb"]){id notebook=[NSJSONSerialization JSONObjectWithData:entry[@"data"] options:0 error:NULL];BOOL ok=[notebook isKindOfClass:NSDictionary.class] && [notebook[@"cells"] isKindOfClass:NSArray.class] && [notebook[@"nbformat"] isKindOfClass:NSNumber.class];if(ok)for(id cell in notebook[@"cells"])if(![cell isKindOfClass:NSDictionary.class] || ![@[@"code",@"markdown",@"raw"] containsObject:cell[@"cell_type"]] || !([cell[@"source"] isKindOfClass:NSString.class] || [cell[@"source"] isKindOfClass:NSArray.class])){ok=NO;break;}if(!ok)[found addObject:PFIssue(@"format",@"error",path,@1,@"Notebook JSON 或单元结构无效",@"",@"用 Notebook 编辑器检查文件；未执行任何单元。")];}
            }else if([entry[@"image"] boolValue]){status=@"已检查：图片可解码";if(!PFImage(entry[@"data"]))[found addObject:PFIssue(@"format",@"error",path,@1,@"图片损坏或超过安全解码尺寸",@"",@"重新导出图片并复查。")];}
            if(cancelled && cancelled())return @{@"cancelled":@YES};
            cached=@{@"issues":found,@"status":status,@"math":math ?: @{}};if(!math || [math[@"completed"] boolValue])cache[key]=cached;
        }
        [issues addObjectsFromArray:cached[@"issues"]];[coverage addObject:@{@"path":path,@"status":cached[@"status"]}];if([cached[@"math"] count])[coverage addObject:@{@"path":path,@"kind":@"math",@"status":[cached[@"math"][@"completed"] boolValue] ? [NSString stringWithFormat:@"已渲染：%lu 个公式（GitHub风格）",(unsigned long)[cached[@"math"][@"formulaCount"] unsignedIntegerValue]]:@"未完成：公式渲染超时、内容超限或渲染器不可用"}];
        if([entry[@"image"] boolValue] && !entry[@"problem"] && PFImage(entry[@"data"]))[images addObject:@{@"path":path,@"document":path,@"line":@1,@"version":entry[@"version"]}];
        NSString *text=entry[@"text"];
        if([@[@"md",@"markdown",@"mdx"] containsObject:path.pathExtension.lowercaseString])for(NSDictionary *ref in AMPreflightImageReferences(text ?: @"")){
            NSString *target=ref[@"reference"],*resolved=AMPreflightResolveImage(path,target);if(PFMatches(target,@"^(?:https?:)?//").count){[issues addObject:PFIssue(@"image",@"info",path,ref[@"line"],@"远程图片可用性未验证",target,@"请自行确认网络图片可用。")];continue;}
            if(!resolved){[issues addObject:PFIssue(@"image",@"warning",path,ref[@"line"],@"图片引用为空、越界或不支持",target,@"改为检查范围内的相对路径；需要上级图片时选择共同父目录。")];continue;}
            NSDictionary *asset=files[resolved];if(!asset || [asset[@"deleted"] boolValue] || asset[@"problem"]){[issues addObject:PFIssue(@"image",@"error",path,ref[@"line"],asset[@"problem"] ?: ([snapshot[@"mode"] isEqual:@"working"] ? @"作业文件夹缺少引用图片":@"拟提交版本缺少图片；本机存在也不代表会上传"),target,([snapshot[@"mode"] isEqual:@"working"] ? @"补齐引用图片后复查；共享图片需要选择共同父目录。":@"返回文件列表，检查是否需要选择这张图片。"))];continue;}
            if(!PFImage(asset[@"data"])){[issues addObject:PFIssue(@"image",@"error",path,ref[@"line"],@"引用图片无法解码",target,@"重新导出图片并复查。")];continue;}
            [images addObject:@{@"path":resolved,@"document":path,@"line":ref[@"line"],@"version":asset[@"version"]}];
        }
    }
    if(progress)progress(total,total);
    if(!RTrim(requirements).length)[issues addObject:PFIssue(@"requirements",@"info",@"",@1,@"未提供题目，无法判断是否完成全部要求",@"",@"关联作业或补充老师原文。")];
    [coverage addObject:@{@"path":@"",@"status":@"未检查：答案、推导、中文语义及程序运行；可交给助手复核"}];
    NSArray *sorted=[issues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){NSArray *levels=@[@"error",@"warning",@"info"];NSUInteger x=[levels indexOfObject:a[@"severity"]],y=[levels indexOfObject:b[@"severity"]];return x<y ? NSOrderedAscending : x>y ? NSOrderedDescending:NSOrderedSame;}];
    NSMutableArray *uniqueImages=NSMutableArray.array;NSMutableSet *imagePaths=NSMutableSet.set;for(NSDictionary *image in images)if(![imagePaths containsObject:image[@"path"]]){[imagePaths addObject:image[@"path"]];[uniqueImages addObject:image];}
    return @{@"version":AMPreflightHash([[NSString stringWithFormat:@"preflight-v3-renderer4|%@|%@",snapshot[@"version"],requirements] dataUsingEncoding:NSUTF8StringEncoding]),@"snapshotVersion":snapshot[@"version"],@"issues":sorted,@"coverage":coverage,@"images":uniqueImages,@"date":NSDate.date,@"assistant":@"未检查"};
}
static BOOL PFWrite(NSData *data,NSURL *url,NSError **error){
    if(![url.path isEqual:url.URLByResolvingSymlinksInPath.path]){if(error)*error=RError(@"交换目录不安全。");return NO;}
    NSString *temp=[url.path stringByAppendingFormat:@".%@.tmp",NSUUID.UUID.UUIDString];int fd=open(temp.fileSystemRepresentation,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0600);if(fd<0)return NO;const unsigned char *p=data.bytes;NSUInteger remaining=data.length;BOOL ok=YES;while(remaining){ssize_t n=write(fd,p,remaining);if(n<=0){ok=NO;break;}p+=n;remaining-=n;}if(fsync(fd))ok=NO;close(fd);if(ok)ok=rename(temp.fileSystemRepresentation,url.path.fileSystemRepresentation)==0;if(!ok){unlink(temp.fileSystemRepresentation);if(error)*error=RError(@"材料或检查记录保存失败，未推进批次。");}return ok;
}
NSDictionary *AMPreflightExport(NSDictionary *report,NSDictionary *snapshot,NSString *requirements,NSArray *images,NSURL *folder,NSError **error){
    if(SSContainsSecret([requirements dataUsingEncoding:NSUTF8StringEncoding])){if(error)*error=RError(@"题目含疑似凭据，请先移除。");return nil;}
    if(![folder.path isEqual:folder.URLByResolvingSymlinksInPath.path] || [NSFileManager.defaultManager fileExistsAtPath:folder.path]){if(error)*error=RError(@"材料目录已经存在或不安全，请重新准备。");return nil;}
    if(![NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error])return nil;
    NSMutableArray *documents=NSMutableArray.array,*assets=NSMutableArray.array;NSUInteger total=0;
    for(NSString *path in snapshot[@"paths"]){NSDictionary *file=snapshot[@"files"][path];if([file[@"version"] isEqual:@"secret"]){if(error)*error=RError(@"所选文件含疑似凭据，无法导出。");return nil;}if(!file[@"text"])continue;if(SSSensitivePath(path) || SSContainsSecret([file[@"text"] dataUsingEncoding:NSUTF8StringEncoding])){if(error)*error=RError(@"材料含疑似凭据，无法导出。");return nil;}total+=[file[@"data"] length];if(total>32*1024*1024){if(error)*error=RError(@"材料总量过大，请减少选择后分批复核。");return nil;}[documents addObject:@{@"path":path,@"version":file[@"version"],@"text":file[@"text"]}];}
    NSMutableSet *seen=NSMutableSet.set;NSUInteger index=0;
    for(NSDictionary *image in images){NSString *path=image[@"path"];if([seen containsObject:path])continue;[seen addObject:path];NSDictionary *source=snapshot[@"files"][path];NSData *png=PFImage(source[@"data"]);if(!png){if(error)*error=RError(@"图片无法解码，未发送材料。");return nil;}total+=png.length;if(total>64*1024*1024){if(error)*error=RError(@"图片材料总量超过64 MB，请减少图片或分批复核。");return nil;}
        NSError *ocrError=nil;NSString *ocr=DDLOCRTextFromImage([[NSImage alloc] initWithData:png],&ocrError);if(ocrError){if(error)*error=RError(@"图片隐私检查未完成，未导出；可排除图片后重试。");return nil;}if(SSContainsSecret([ocr dataUsingEncoding:NSUTF8StringEncoding])){if(error)*error=RError(@"图片文字含疑似凭据，请先排除该图片。");return nil;}
        NSString *resource=[NSString stringWithFormat:@"image-%lu.png",(unsigned long)++index];if(!PFWrite(png,[folder URLByAppendingPathComponent:resource],error))return nil;
        [assets addObject:@{@"id":resource,@"path":path,@"document":image[@"document"],@"line":image[@"line"],@"version":source[@"version"],@"resource":resource,@"resourceHash":AMPreflightHash(png)}];
    }
    NSMutableArray *excluded=NSMutableArray.array;for(NSDictionary *image in report[@"images"])if(![seen containsObject:image[@"path"]])[excluded addObject:[NSString stringWithFormat:@"%@：用户排除的图片未交给助手",image[@"path"]]];
    for(NSDictionary *row in report[@"coverage"]){NSString *path=row[@"path"];if(snapshot[@"files"][path][@"text"] && ![snapshot[@"paths"] containsObject:path])[excluded addObject:[NSString stringWithFormat:@"%@：用户排除的文档未交给助手",path]];}
    NSDictionary *context=@{@"unverifiedImages":excluded,@"format":@"am-preflight-context-v1",@"batchID":folder.lastPathComponent,@"reportVersion":report[@"version"],@"snapshotVersion":snapshot[@"version"],@"requirements":requirements ?: @"",@"documents":documents,@"images":assets};
    NSData *json=[NSJSONSerialization dataWithJSONObject:context options:NSJSONWritingPrettyPrinted error:error];if(!json || !PFWrite(json,[folder URLByAppendingPathComponent:@"context.local.json"],error))return nil;
    NSString *skill=[NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"am-homework-extract" ofType:@"md"] ?: @"Skills/am-homework-extract/SKILL.md" encoding:NSUTF8StringEncoding error:NULL];if(!skill.length || !PFWrite([skill dataUsingEncoding:NSUTF8StringEncoding],[folder URLByAppendingPathComponent:@"SKILL.md"],error))return nil;
    return context;
}
NSDictionary *AMPreflightValidateResult(id result,NSDictionary *context,NSError **error){
    if(![result isKindOfClass:NSDictionary.class] || ![result[@"format"] isEqual:@"am-preflight-results-v1"] || ![result[@"batchID"] isEqual:context[@"batchID"]] || ![result[@"reportVersion"] isEqual:context[@"reportVersion"]] || ![result[@"findings"] isKindOfClass:NSArray.class] || [result[@"findings"] count]>1000 || ![result[@"checked"] isKindOfClass:NSArray.class] || ![result[@"unverified"] isKindOfClass:NSArray.class] || [result[@"checked"] count]>1000 || [result[@"unverified"] count]>1000){if(error)*error=RError(@"复核结果格式或版本不匹配。");return nil;}
    NSMutableDictionary *sources=NSMutableDictionary.dictionary;for(NSDictionary *d in context[@"documents"])sources[d[@"path"]]=d;for(NSDictionary *d in context[@"images"])sources[d[@"path"]]=d;
    NSMutableArray *issues=NSMutableArray.array,*invalid=NSMutableArray.array;NSMutableSet *seen=NSMutableSet.set;
    for(id value in result[@"findings"]){BOOL valid=[value isKindOfClass:NSDictionary.class];NSDictionary *source=valid && [value[@"path"] isKindOfClass:NSString.class] ? sources[value[@"path"]]:nil;
        for(NSString *field in @[@"path",@"version",@"category",@"severity",@"message",@"reason",@"suggestion"])if(![value isKindOfClass:NSDictionary.class] || ![value[field] isKindOfClass:NSString.class] || [value[field] length]>10000)valid=NO;
        if(!valid || !source || ![source[@"version"] isEqual:value[@"version"]] || ![@[@"format",@"image",@"incomplete",@"spelling",@"answer",@"rigor",@"unreadable"] containsObject:value[@"category"]] || ![@[@"error",@"warning",@"info"] containsObject:value[@"severity"]])valid=NO;
        if(valid && source[@"text"]){NSString *evidence=value[@"evidence"];NSNumber *line=value[@"line"];NSArray *lines=[source[@"text"] componentsSeparatedByString:@"\n"];if(![evidence isKindOfClass:NSString.class] || !evidence.length || ![line isKindOfClass:NSNumber.class] || line.integerValue<1 || line.integerValue>(NSInteger)lines.count)valid=NO;else {NSString *tail=[[lines subarrayWithRange:NSMakeRange(line.unsignedIntegerValue-1,lines.count-line.unsignedIntegerValue+1)] componentsJoinedByString:@"\n"];if(![tail hasPrefix:evidence] && [lines[line.unsignedIntegerValue-1] rangeOfString:evidence].location==NSNotFound)valid=NO;}}
        else if(valid){NSArray *rect=value[@"region"];if(![rect isKindOfClass:NSArray.class] || rect.count!=4)valid=NO;else{for(id n in rect)if(![n isKindOfClass:NSNumber.class] || !isfinite([n doubleValue]) || [n doubleValue]<0 || [n doubleValue]>1)valid=NO;if(valid && ([rect[2] doubleValue]<=0 || [rect[3] doubleValue]<=0 || [rect[0] doubleValue]+[rect[2] doubleValue]>1 || [rect[1] doubleValue]+[rect[3] doubleValue]>1))valid=NO;}}
        if(!valid){[invalid addObject:@"一条建议的位置、版本或证据无效，已排除"];continue;}
        NSData *encoded=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:NULL];if(SSContainsSecret(encoded)){[invalid addObject:@"一条建议含疑似凭据，已排除"];continue;}NSString *identity=AMPreflightHash(encoded);if([seen containsObject:identity])continue;[seen addObject:identity];NSMutableDictionary *copy=[value mutableCopy];if([copy[@"category"] isEqual:@"unreadable"] || ![copy[@"message"] hasPrefix:@"明确问题"]){if([copy[@"severity"] isEqual:@"error"])copy[@"severity"]=@"warning";}if([copy[@"message"] hasPrefix:@"表达建议"])copy[@"severity"]=@"info";copy[@"id"]=identity;copy[@"provider"]=@"assistant";[issues addObject:copy];
    }
    NSMutableSet *checked=NSMutableSet.set;for(id item in result[@"checked"])if([item isKindOfClass:NSDictionary.class] && [item[@"path"] isKindOfClass:NSString.class] && [sources[item[@"path"]][@"version"] isEqual:item[@"version"]])[checked addObject:item[@"path"]];
    NSMutableArray *unverified=NSMutableArray.array;for(NSString *path in sources)if(![checked containsObject:path])[unverified addObject:[NSString stringWithFormat:@"%@：助手未完成检查",path]];
    for(id reason in result[@"unverified"])if([reason isKindOfClass:NSString.class] && [reason length]<1000 && !SSContainsSecret([reason dataUsingEncoding:NSUTF8StringEncoding]))[unverified addObject:reason];
    [unverified addObjectsFromArray:context[@"unverifiedImages"] ?: @[]];[unverified addObjectsFromArray:invalid];return @{@"issues":issues,@"unverified":unverified,@"checked":checked.allObjects,@"partial":@(unverified.count>0),@"reportVersion":context[@"reportVersion"]};
}
static NSData *PFRead(NSURL *url,NSUInteger limit){
    if(!url || ![url.path isEqual:url.URLByResolvingSymlinksInPath.path])return nil;
    int fd=open(url.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK);if(fd<0)return nil;struct stat st;NSMutableData *data=NSMutableData.data;
    if(fstat(fd,&st)!=0 || !S_ISREG(st.st_mode) || st.st_size<0 || (unsigned long long)st.st_size>limit){close(fd);return nil;}
    char buffer[8192];ssize_t n;while((n=read(fd,buffer,sizeof(buffer)))>0){if(data.length+(NSUInteger)n>limit){close(fd);return nil;}[data appendBytes:buffer length:(NSUInteger)n];}close(fd);return n==0 ? data:nil;
}
NSURL *AMPreflightFolder(NSString *batch){if(![[NSUUID alloc] initWithUUIDString:batch])return nil;NSURL *folder=[[SSDataDirectory().URLByResolvingSymlinksInPath URLByAppendingPathComponent:@"preflight"] URLByAppendingPathComponent:batch];return [folder.path isEqual:folder.URLByResolvingSymlinksInPath.path] ? folder:nil;}
NSDictionary *AMPreflightSavedSnapshot(NSString *batch){
    NSURL *folder=AMPreflightFolder(batch);NSData *data=PFRead([folder URLByAppendingPathComponent:@"context.local.json"],32*1024*1024);BOOL intact=NO;for(NSDictionary *job in AMPreflightJobs())if([job[@"id"] isEqual:batch] && [job[@"contextHash"] isEqual:AMPreflightHash(data ?: NSData.data)])intact=YES;id context=intact && data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;if(![context isKindOfClass:NSDictionary.class] || ![context[@"batchID"] isEqual:batch] || ![context[@"images"] isKindOfClass:NSArray.class])return @{@"files":@{},@"paths":@[]};
    NSMutableDictionary *files=NSMutableDictionary.dictionary;for(id row in context[@"images"]){if(![row isKindOfClass:NSDictionary.class] || ![row[@"resource"] isKindOfClass:NSString.class] || ![row[@"path"] isKindOfClass:NSString.class] || ![row[@"resource"] isEqual:[row[@"resource"] lastPathComponent]])continue;NSData *png=PFRead([folder URLByAppendingPathComponent:row[@"resource"]],64*1024*1024);if(png && [AMPreflightHash(png) isEqual:row[@"resourceHash"]])files[row[@"path"]]=@{@"image":@YES,@"data":png};}return @{@"files":files,@"paths":@[]};
}
static NSArray *PFJobsRead(void){id saved=SSReadPlist(@"preflight-jobs.plist");if(!saved)return [NSFileManager.defaultManager fileExistsAtPath:[[SSDataDirectory() URLByAppendingPathComponent:@"preflight-jobs.plist"] path]] ? nil:@[];if(![saved isKindOfClass:NSArray.class] || [saved count]>1000)return nil;for(id row in saved)if(![row isKindOfClass:NSDictionary.class] || ![row[@"id"] isKindOfClass:NSString.class] || !AMPreflightFolder(row[@"id"]) || ![row[@"date"] isKindOfClass:NSDate.class] || ![row[@"contextHash"] isKindOfClass:NSString.class] || ![row[@"report"] isKindOfClass:NSDictionary.class])return nil;return saved;}
NSArray *AMPreflightJobs(void){@synchronized(NSSpellChecker.class){return PFJobsRead() ?: @[];}}
BOOL AMPreflightRegister(NSDictionary *context,NSDictionary *report,NSString *courseID,NSError **error){@synchronized(NSSpellChecker.class){NSArray *old=PFJobsRead();if(!old || old.count>=1000){if(error)*error=RError(@"复核批次记录无法读取或已满，原记录已保留。");return NO;}NSData *data=PFRead([AMPreflightFolder(context[@"batchID"]) URLByAppendingPathComponent:@"context.local.json"],32*1024*1024);if(!data)return NO;NSMutableArray *next=old.mutableCopy;[next addObject:@{@"id":context[@"batchID"],@"date":NSDate.date,@"state":@"等待助手",@"message":@"提交前复核；结果供核对，不会自动提交",@"count":@([context[@"documents"] count]),@"courses":courseID.length ? @[courseID]:@[],@"contextHash":AMPreflightHash(data),@"report":report,@"reportVersion":report[@"version"]}];return SSWritePlist(@"preflight-jobs.plist",next,error);}}
NSDictionary *AMPreflightJobForReport(NSString *version){for(NSDictionary *job in [AMPreflightJobs() reverseObjectEnumerator])if([job[@"reportVersion"] isEqual:version])return job;return nil;}
void AMPreflightPoll(void){@synchronized(NSSpellChecker.class){NSArray *old=PFJobsRead();if(!old)return;NSMutableArray *next=NSMutableArray.array,*operations=NSMutableArray.array;BOOL dirty=NO;
    for(NSDictionary *value in old){NSMutableDictionary *job=value.mutableCopy;[next addObject:job];if([job[@"state"] isEqual:@"已接回"] && ![job[@"cleaned"] boolValue] && [job[@"date"] timeIntervalSinceNow]<-30*86400){NSURL *folder=AMPreflightFolder(job[@"id"]);if(folder)[NSFileManager.defaultManager removeItemAtURL:folder error:NULL];job[@"cleaned"]=@YES;job[@"report"]=@{};[job removeObjectForKey:@"result"];dirty=YES;}
        if([job[@"state"] isEqual:@"已接回"] || [job[@"cleaned"] boolValue])continue;NSURL *folder=AMPreflightFolder(job[@"id"]);NSURL *url=[folder URLByAppendingPathComponent:@"results.local.json"];if(![NSFileManager.defaultManager fileExistsAtPath:url.path])continue;NSError *failure=nil;NSDictionary *read=SSSkillReadResult(url,&failure);NSString *fingerprint=read[@"fingerprint"];if(fingerprint && [job[@"fingerprint"] isEqual:fingerprint])continue;
        NSString *operation=AMOperationBegin(@"核验并接回复核结果",[job[@"provider"] isEqual:@"Gemini"] ? @"Gemini":@"Skill",NO,nil);
        NSURL *contextURL=[folder URLByAppendingPathComponent:@"context.local.json"];NSData *data=PFRead(contextURL,32*1024*1024);NSDictionary *context=data.length<=32*1024*1024 ? [NSJSONSerialization JSONObjectWithData:data ?: NSData.data options:0 error:NULL]:nil;
        BOOL intact=[AMPreflightHash(data ?: NSData.data) isEqual:job[@"contextHash"]];
        if(intact)for(NSDictionary *image in context[@"images"]){NSString *resource=image[@"resource"];if(![resource isEqual:resource.lastPathComponent] || ![AMPreflightHash(PFRead([folder URLByAppendingPathComponent:resource],64*1024*1024) ?: NSData.data) isEqual:image[@"resourceHash"]]){intact=NO;break;}}
        NSDictionary *result=read && intact ? AMPreflightValidateResult(read[@"result"],context,&failure):nil;
        if(result){job[@"result"]=result;job[@"state"]=[result[@"partial"] boolValue] ? @"需处理":@"已接回";job[@"message"]=[NSString stringWithFormat:@"提交前复核：%lu 条建议%@；仅适用于导出版本",(unsigned long)[result[@"issues"] count],[result[@"partial"] boolValue] ? @"，部分未完成":@""];}
        else {job[@"state"]=@"需处理";job[@"message"]=failure.localizedDescription ?: @"复核材料版本变化，请重新准备材料。";}
        if([job[@"provider"] isEqual:@"Gemini"])job[@"message"]=[@"Gemini · " stringByAppendingString:job[@"message"]];
        if(fingerprint)job[@"fingerprint"]=fingerprint;dirty=YES;[operations addObject:@{@"id":operation,@"state":result ? @"success":@"failed",@"message":job[@"message"]}];
    }
    BOOL saved=!dirty || SSWritePlist(@"preflight-jobs.plist",next,NULL);for(NSDictionary *operation in operations)AMOperationFinish(operation[@"id"],saved ? operation[@"state"]:@"failed",saved ? operation[@"message"]:@"接回保存失败，可重试");
}}
BOOL AMPreflightJobAction(NSString *action,NSString *batch){@synchronized(NSSpellChecker.class){NSArray *old=PFJobsRead();if(!old)return NO;BOOL clean=[action isEqual:@"clean"],matched=NO;NSMutableArray *next=NSMutableArray.array;
    for(NSDictionary *value in old){NSMutableDictionary *job=value.mutableCopy;[next addObject:job];BOOL target=clean ? [job[@"state"] isEqual:@"已接回"]:[job[@"id"] isEqual:batch];if(!target)continue;matched=YES;NSURL *folder=AMPreflightFolder(job[@"id"]);
        if(clean){if(folder && ![job[@"cleaned"] boolValue]){[NSFileManager.defaultManager removeItemAtURL:folder error:NULL];job[@"cleaned"]=@YES;[job removeObjectForKey:@"result"];job[@"report"]=@{};}}
        else if([action isEqual:@"retry"] || [action isEqual:@"prepare-failed"]){[job removeObjectForKey:@"fingerprint"];job[@"state"]=@"等待助手";job[@"message"]=@"等待重新接回复核结果";}
        else if([action isEqual:@"copy"]){NSString *prompt=[NSFileManager.defaultManager fileExistsAtPath:[[folder URLByAppendingPathComponent:@"AM-Helper-review.zip"] path]] ? AMPreflightAttachmentPrompt():[NSString stringWithFormat:@"仅用于可访问本机文件的助手：读取 %@ 中的 SKILL.md 和 context.local.json，按提交前复核模式检查文本与图片。将结果先写入 results.local.json.tmp，再原子重命名为 results.local.json；不修改作业或执行代码。",folder.path];[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:prompt forType:NSPasteboardTypeString];}
        else if([action isEqual:@"reveal"])[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[folder]];
    }
    if(clean || [action isEqual:@"retry"] || [action isEqual:@"prepare-failed"])if(matched)SSWritePlist(@"preflight-jobs.plist",next,NULL);return matched;
}}
// A portable handoff contains only the already reviewed, registered materials.
static NSDictionary *PFContextForBatch(NSString *batch,NSError **error){
    NSURL *folder=AMPreflightFolder(batch);NSData *data=PFRead([folder URLByAppendingPathComponent:@"context.local.json"],32*1024*1024);NSDictionary *context=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;BOOL intact=NO;
    for(NSDictionary *job in AMPreflightJobs())if([job[@"id"] isEqual:batch] && [job[@"contextHash"] isEqual:AMPreflightHash(data ?: NSData.data)])intact=YES;
    if(intact && [context isKindOfClass:NSDictionary.class] && [context[@"batchID"] isEqual:batch]){
        for(NSDictionary *image in context[@"images"]){NSString *name=image[@"resource"];if(![name isEqual:name.lastPathComponent] || ![AMPreflightHash(PFRead([folder URLByAppendingPathComponent:name],64*1024*1024) ?: NSData.data) isEqual:image[@"resourceHash"]]){intact=NO;break;}}
    }else intact=NO;
    if(!intact){if(error)*error=RError(@"本机复核材料已变化或清理，请重新准备。");return nil;}return context;
}
NSString *AMPreflightAttachmentPrompt(void){return @"请解压我上传的 AM-Helper-review.zip，读取其中的 SKILL.md 与 context.local.json，按提交前复核模式检查文本和图片。不执行代码、不修改作业。只检查附件中的材料；看不清的符号或无法读取的文件列入 unverified。按 Skill 格式返回可下载的 results.local.json，保留 batchID、reportVersion、文件 version 与原文证据。你无需访问我的 Mac 路径；我会在 AM Helper 的检查报告中点‘导入助手结果…’接回。若不能读取 ZIP，请说明，我会解压后上传其中的文件。";}
NSURL *AMPreflightAttachmentArchive(NSString *batch,NSError **error){
    NSDictionary *context=PFContextForBatch(batch,error);if(!context)return nil;NSURL *folder=AMPreflightFolder(batch);
    NSString *readme=@"提交前作业复核\n\n在支持附件的助手中上传本 ZIP；如不支持 ZIP，请解压后上传 SKILL.md、context.local.json 和 image-*.png。\n按 SKILL.md 的 Pre-submission review 模式检查，只返回 results.local.json。\n下载结果后，在 AM Helper 检查报告中选择‘导入助手结果…’。\n本包不提供访问原电脑的能力；不会自动上传材料或提交作业。\n";
    if(!PFWrite([readme dataUsingEncoding:NSUTF8StringEncoding],[folder URLByAppendingPathComponent:@"README.txt"],error))return nil;
    NSMutableArray *names=[@[@"SKILL.md",@"context.local.json",@"README.txt"] mutableCopy];for(NSDictionary *image in context[@"images"])[names addObject:image[@"resource"]];
    // Freeze validated bytes into an isolated staging directory. ZIP never re-reads
    // the watched batch directory or any original homework file.
    NSURL *stage=[folder URLByAppendingPathComponent:[NSString stringWithFormat:@"attachment-%@",NSUUID.UUID.UUIDString]];
    if(![NSFileManager.defaultManager createDirectoryAtURL:stage withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:error])return nil;
    @try {
        for(NSString *name in names){NSData *data=PFRead([folder URLByAppendingPathComponent:name],64*1024*1024);BOOL valid=data!=nil;
            if([name isEqual:@"context.local.json"])valid=valid && [[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] isEqual:context];
            for(NSDictionary *image in context[@"images"])if([image[@"resource"] isEqual:name])valid=valid && [AMPreflightHash(data ?: NSData.data) isEqual:image[@"resourceHash"]];
            if(![name hasPrefix:@"image-"] && SSContainsSecret(data))valid=NO;
            if(!valid || !PFWrite(data,[stage URLByAppendingPathComponent:name],error)){if(error && !*error)*error=RError(@"材料已变化或含疑似凭据，未创建附件包。");return nil;}
        }
        NSURL *temp=[stage URLByAppendingPathComponent:@"attachment.zip"];NSTask *task=NSTask.new;task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/zip"];task.currentDirectoryURL=stage;task.arguments=[@[@"-q",@"-X",temp.lastPathComponent] arrayByAddingObjectsFromArray:names];task.environment=@{@"PATH":@"/usr/bin:/bin",@"LC_ALL":@"C"};task.standardOutput=NSFileHandle.fileHandleWithNullDevice;task.standardError=NSFileHandle.fileHandleWithNullDevice;
        if(![task launchAndReturnError:error])return nil;[task waitUntilExit];NSData *zip=task.terminationStatus==0 ? PFRead(temp,100*1024*1024):nil;NSURL *archive=[folder URLByAppendingPathComponent:@"AM-Helper-review.zip"];BOOL ok=zip && PFWrite(zip,archive,error);if(!ok && error && !*error)*error=RError(@"附件包未创建，请重试。");return ok ? archive:nil;
    }@finally{[NSFileManager.defaultManager removeItemAtURL:stage error:NULL];}

}
BOOL AMPreflightImportResult(NSURL *url,NSString *batch,NSError **error){
    @synchronized(NSSpellChecker.class){
        NSDictionary *context=PFContextForBatch(batch,error),*read=context ? SSSkillReadResult(url,error):nil;
        if(!read || !AMPreflightValidateResult(read[@"result"],context,error))return NO;
        for(NSDictionary *job in AMPreflightJobs())if([job[@"id"] isEqual:batch] && [job[@"state"] isEqual:@"已接回"]){NSDictionary *saved=SSSkillReadResult([AMPreflightFolder(batch) URLByAppendingPathComponent:@"results.local.json"],NULL);if([saved[@"result"] isEqual:read[@"result"]])return YES;if(error)*error=RError(@"此批次已经接回。需要重新复核时请准备新材料。");return NO;}
        NSData *data=[NSJSONSerialization dataWithJSONObject:read[@"result"] options:NSJSONWritingPrettyPrinted error:error];if(!data || !PFWrite(data,[AMPreflightFolder(batch) URLByAppendingPathComponent:@"results.local.json"],error))return NO;
        AMPreflightPoll();NSString *fingerprint=SSSkillReadResult([AMPreflightFolder(batch) URLByAppendingPathComponent:@"results.local.json"],NULL)[@"fingerprint"];for(NSDictionary *job in AMPreflightJobs())if([job[@"id"] isEqual:batch] && job[@"result"] && [job[@"fingerprint"] isEqual:fingerprint])return YES;
        if(error)*error=RError(@"结果未保存到报告；文件已保留，可重试。");return NO;
    }
}
