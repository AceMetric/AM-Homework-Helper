#import "SSSecurity.h"
#import <zlib.h>

static NSArray<NSString *> *SecretPatterns(void) {
    return @[@"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----",
             @"(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})",
             @"(?:AKIA|ASIA)[0-9A-Z]{16}",
             @"sk-(?:proj-)?[A-Za-z0-9_-]{24,}",
             @"AIza[A-Za-z0-9_-]{35}",
             @"(?i)[\"']?(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|aws_secret_access_key)[\"']?\\s*[:=]\\s*[\"'][A-Za-z0-9_./+=-]{12,}[\"']"];
}
NSString *SSCanonicalRepository(NSString *url) {
    NSString *value = [url stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(?:git@github\\.com:|ssh://git@github\\.com/|https://github\\.com/)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\\.git)?/?$" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *match = [regex firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
    if (!match) return nil;
    NSString *repo = [[value substringWithRange:[match rangeAtIndex:1]] lowercaseString];
    NSArray *parts = [repo componentsSeparatedByString:@"/"];
    for (NSString *part in parts) if ([part hasPrefix:@"."] || [part isEqual:@"-"]) return nil;
    return repo;
}
BOOL SSValidBranch(NSString *branch) {
    if (!branch.length || [branch hasPrefix:@"-"] || [branch containsString:@".."] || [branch containsString:@"//"] || [branch containsString:@"@{"] || [branch hasSuffix:@"/"] || [branch hasSuffix:@"."]) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-"];
    if ([branch rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return NO;
    for (NSString *part in [branch componentsSeparatedByString:@"/"]) if ([part hasPrefix:@"."] || [part hasSuffix:@".lock"]) return NO;
    return YES;
}
BOOL SSSensitivePath(NSString *path) {
    NSArray *parts = path.lowercaseString.pathComponents;
    for (NSString *part in parts) if ([@[@".git", @".ssh", @".aws", @".gnupg"] containsObject:part]) return YES;
    NSString *name = path.lastPathComponent.lowercaseString;
    if ([@[@".env", @".npmrc", @".pypirc", @".netrc", @"id_rsa", @"id_ed25519", @"id_ecdsa", @"credentials", @"credentials.json", @"auth.json"] containsObject:name]) return YES;
    if ([name hasPrefix:@".env."] && ![@[@"example", @"sample", @"template"] containsObject:name.pathExtension]) return YES;
    return [@[@"pem", @"p12", @"pfx", @"key", @"mobileprovision", @"zip", @"7z", @"rar", @"tar"] containsObject:name.pathExtension];
}
BOOL SSValidatedTrainingData(NSData *data){
    if(!data.length || data.length>64*1024*1024)return NO;const unsigned char *bytes=data.bytes;NSData *decoded=data;
    if(data.length>=2 && bytes[0]==0x1f && bytes[1]==0x8b){if(data.length<18)return NO;NSUInteger n=data.length;uint32_t expanded=((uint32_t)bytes[n-1]<<24)|((uint32_t)bytes[n-2]<<16)|((uint32_t)bytes[n-3]<<8)|bytes[n-4];if(expanded>64*1024*1024)return NO;z_stream stream={0};stream.next_in=(Bytef *)data.bytes;stream.avail_in=(uInt)data.length;if(inflateInit2(&stream,15+16)!=Z_OK)return NO;NSMutableData *output=NSMutableData.data;unsigned char block[65536];int state=Z_OK;
        while(state==Z_OK){stream.next_out=block;stream.avail_out=sizeof(block);state=inflate(&stream,Z_NO_FLUSH);NSUInteger count=sizeof(block)-stream.avail_out;if(output.length+count>64*1024*1024){inflateEnd(&stream);return NO;}[output appendBytes:block length:count];}
        BOOL valid=state==Z_STREAM_END && stream.avail_in==0;inflateEnd(&stream);if(!valid)return NO;decoded=output;
    }
    bytes=decoded.bytes;if(decoded.length<8 || bytes[0] || bytes[1] || bytes[2]!=8 || bytes[3]<1 || bytes[3]>4)return NO;
    NSUInteger header=4+4*bytes[3];if(decoded.length<header)return NO;uint64_t count=1;
    for(NSUInteger i=0;i<bytes[3];i++){NSUInteger offset=4+i*4;uint32_t dimension=((uint32_t)bytes[offset]<<24)|((uint32_t)bytes[offset+1]<<16)|((uint32_t)bytes[offset+2]<<8)|bytes[offset+3];if(!dimension || dimension>64*1024*1024/count)return NO;count*=dimension;}
    return decoded.length==header+count && !SSContainsSecret(data) && (decoded==data || !SSContainsSecret(decoded));
}
BOOL SSContainsSecret(NSData *data) {
    if (!data.length) return NO;
    // Scan raw bytes as Latin-1 as well as UTF text: binary prefixes must not hide ASCII secrets.
    for (NSNumber *encoding in @[@(NSISOLatin1StringEncoding), @(NSUTF8StringEncoding), @(NSUTF16StringEncoding)]) {
        NSString *text = [[NSString alloc] initWithData:data encoding:encoding.unsignedIntegerValue];
        if (!text) continue;
        for (NSString *pattern in SecretPatterns()) {
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
            if ([regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;
        }
    }
    return NO;
}
NSString *SSRedactedContent(NSString *text) {
    NSString *result = text ?: @"";
    NSArray *patterns = [SecretPatterns() arrayByAddingObjectsFromArray:@[@"(?i)https?://[^/\\s]+@", @"(?i)(?:authorization|bearer)\\s*[:=]?\\s+[A-Za-z0-9_./+=-]{10,}"]];
    for (NSString *pattern in patterns) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
        result = [regex stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:@"[已隐藏凭据]"];
    }
    NSString *home = NSHomeDirectory();
    if (home.length) result = [result stringByReplacingOccurrencesOfString:home withString:@"~"];
    return result;
}
NSString *SSRedactedText(NSString *text) {
    NSString *result=SSRedactedContent(text);
    return result.length > 1600 ? [result substringToIndex:1600] : result;
}
