#import "AMPreflight.h"

NS_INLINE BOOL AMScoringImagesValid(id images){
    if(![images isKindOfClass:NSArray.class] || [images count]>64)return NO;NSUInteger total=0;NSMutableSet *paths=NSMutableSet.set;
    for(id row in images){if(![row isKindOfClass:NSDictionary.class] || ![row[@"path"] isKindOfClass:NSString.class] || ![row[@"path"] length] || [paths containsObject:row[@"path"]] || ![@[@"image/png",@"image/jpeg"] containsObject:row[@"mime"]] || ![row[@"base64"] isKindOfClass:NSString.class] || [row[@"base64"] length]>28*1024*1024)return NO;NSData *bytes=[[NSData alloc] initWithBase64EncodedString:row[@"base64"] options:0];if(!bytes.length)return NO;total+=bytes.length;if(total>24*1024*1024)return NO;[paths addObject:row[@"path"]];}return YES;
}

// All providers consume the same document-order stream. The JSON envelope holds
// identity/roles; each source text occurs once, followed by its referenced images.
NS_INLINE NSArray *AMScoringSegments(NSDictionary *input,NSArray *images){
    NSMutableDictionary *envelope=input.mutableCopy,*assets=NSMutableDictionary.dictionary;
    for(NSDictionary *image in images)assets[image[@"path"]]=image;
    NSMutableArray *metadata=NSMutableArray.array;NSArray *materials=[input[@"materials"] isKindOfClass:NSArray.class] ? input[@"materials"]:@[];
    for(NSDictionary *material in materials){NSMutableDictionary *record=material.mutableCopy;[record removeObjectForKey:@"text"];[metadata addObject:record];}
    envelope[@"materials"]=metadata;NSData *json=[NSJSONSerialization dataWithJSONObject:envelope options:NSJSONWritingSortedKeys error:NULL];
    NSMutableArray *segments=[NSMutableArray arrayWithObject:@{@"text":[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"{}"}];NSMutableSet *sent=NSMutableSet.set;
    for(NSDictionary *material in materials){NSString *text=material[@"text"];if(![text isKindOfClass:NSString.class])continue;NSArray *lines=[text componentsSeparatedByString:@"\n"];NSArray *occurrences=AMPreflightImageReferences(text);NSMutableArray *headings=NSMutableArray.array;NSMutableString *chunk=NSMutableString.string;NSUInteger start=1;
        for(NSUInteger i=0;i<lines.count;i++){
            NSString *line=lines[i];if([line hasPrefix:@"#"]){NSUInteger level=0;while(level<line.length && [line characterAtIndex:level]=='#')level++;if(level<=6 && level<line.length && [line characterAtIndex:level]==' '){while(headings.count && [headings.lastObject[@"level"] unsignedIntegerValue]>=level)[headings removeLastObject];[headings addObject:@{@"level":@(level),@"title":line}];}}
            if(chunk.length)[chunk appendString:@"\n"];[chunk appendString:line];
            for(NSDictionary *occurrence in occurrences)if([occurrence[@"line"] unsignedIntegerValue]==i+1){NSString *path=AMPreflightResolveImage(material[@"path"],occurrence[@"reference"]);NSDictionary *image=path ? assets[path]:nil;if(!image)continue;
                NSDictionary *source=@{@"path":material[@"path"],@"version":material[@"version"] ?: @"",@"role":material[@"role"] ?: @"answer",@"startLine":@(start),@"text":chunk.copy};NSData *sourceJSON=[NSJSONSerialization dataWithJSONObject:source options:0 error:NULL];[segments addObject:@{@"text":[[NSString alloc] initWithData:sourceJSON encoding:NSUTF8StringEncoding]}];[chunk setString:@""];start=i+2;
                NSDictionary *label=@{@"image":path,@"document":material[@"path"],@"line":@(i+1),@"headings":headings.copy,@"role":material[@"role"] ?: @"answer",@"repeated":@([sent containsObject:path])};NSData *labelJSON=[NSJSONSerialization dataWithJSONObject:label options:0 error:NULL];[segments addObject:@{@"text":[[NSString alloc] initWithData:labelJSON encoding:NSUTF8StringEncoding]}];if(![sent containsObject:path]){[segments addObject:@{@"image":image}];[sent addObject:path];}
            }
        }
        if(chunk.length){NSDictionary *source=@{@"path":material[@"path"],@"version":material[@"version"] ?: @"",@"role":material[@"role"] ?: @"answer",@"startLine":@(start),@"text":chunk};NSData *data=[NSJSONSerialization dataWithJSONObject:source options:0 error:NULL];[segments addObject:@{@"text":[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]}];}
    }
    for(NSDictionary *image in images)if(![sent containsObject:image[@"path"]]){NSMutableDictionary *label=[@{@"image":image[@"path"],@"embedded":@NO} mutableCopy];for(NSDictionary *material in materials)if([material[@"path"] isEqual:image[@"path"]]){label[@"role"]=material[@"role"] ?: @"answer";if(material[@"page"])label[@"page"]=material[@"page"];}NSData *data=[NSJSONSerialization dataWithJSONObject:label options:0 error:NULL];[segments addObject:@{@"text":[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]}];[segments addObject:@{@"image":image}];[sent addObject:image[@"path"]];}
    return segments;
}
