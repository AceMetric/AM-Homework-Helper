// Convert Notebook JSON into review text, without exposing metadata, HTML or encoded images.
static NSString *PFNotebookString(id value){
    if([value isKindOfClass:NSString.class])return value;
    if(![value isKindOfClass:NSArray.class])return nil;
    for(id line in value)if(![line isKindOfClass:NSString.class])return nil;
    return [value componentsJoinedByString:@""];
}

NSDictionary *AMPreflightNotebook(NSData *data,NSString *path){
    id notebook=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if(![notebook isKindOfClass:NSDictionary.class] || ![notebook[@"nbformat"] isKindOfClass:NSNumber.class] || ![notebook[@"cells"] isKindOfClass:NSArray.class])
        return @{@"problem":@"Notebook 无法读取，未覆盖"};
    NSMutableArray *lines=NSMutableArray.array,*omissions=NSMutableArray.array;
    NSMutableDictionary *images=NSMutableDictionary.dictionary;
    NSUInteger characters=0,imageBytes=0;
    void (^append)(NSString *)=^(NSString *text){[lines addObjectsFromArray:[text componentsSeparatedByString:@"\n"]];};
    NSArray *cells=notebook[@"cells"];
    for(NSUInteger i=0;i<cells.count;i++){
        if(i>=512 || characters>=128000){[omissions addObject:[NSString stringWithFormat:@"第 %lu–%lu 单元格超出文字检查额度",(unsigned long)i+1,(unsigned long)cells.count]];break;}
        id cell=cells[i];
        NSString *kind=[cell isKindOfClass:NSDictionary.class] ? cell[@"cell_type"]:nil;
        NSString *source=kind ? PFNotebookString(cell[@"source"]):nil;
        if(!source || ![@[@"markdown",@"code",@"raw"] containsObject:kind]){
            [omissions addObject:[NSString stringWithFormat:@"第 %lu 单元格不可读",(unsigned long)i+1]];continue;
        }
        NSString *label=[NSString stringWithFormat:@"第 %lu 单元格",(unsigned long)i+1];
        append([NSString stringWithFormat:@"## %@ · %@",label,kind]);
        NSUInteger length=MIN(source.length,128000-characters);
        if(length<source.length){[omissions addObject:[label stringByAppendingString:@"的正文超出文字检查额度"]];length=[source rangeOfComposedCharacterSequenceAtIndex:length].location;}
        append([source substringToIndex:length]);characters+=length;
        id outputs=cell[@"outputs"];
        if(!outputs)continue;
        if(![outputs isKindOfClass:NSArray.class]){[omissions addObject:[label stringByAppendingString:@"的输出不可读"]];continue;}
        NSUInteger outputIndex=0,textBytes=0;
        for(id output in outputs){
            if(++outputIndex>32){[omissions addObject:[label stringByAppendingString:@"有更多输出未覆盖"]];break;}
            if(![output isKindOfClass:NSDictionary.class]){[omissions addObject:[label stringByAppendingString:@"的输出不可读"]];continue;}
            id mime=output[@"data"];
            NSDictionary *bundle=[mime isKindOfClass:NSDictionary.class] ? mime:@{};
            NSString *plain=PFNotebookString(output[@"text"] ?: bundle[@"text/plain"] ?: output[@"traceback"]);
            if(plain.length){
                NSUInteger count=MIN(plain.length,4000-textBytes);
                if(count<plain.length)[omissions addObject:[label stringByAppendingString:@"的文字输出已截断"]];
                if(count && count<plain.length)count=[plain rangeOfComposedCharacterSequenceAtIndex:count].location;
                if(count){append([NSString stringWithFormat:@"输出 %lu（文字）",(unsigned long)outputIndex]);append([plain substringToIndex:count]);textBytes+=count;characters+=count;}
            }
            NSString *encoded=PFNotebookString(bundle[@"image/png"] ?: bundle[@"image/jpeg"]);
            if(encoded){
                NSData *image=encoded.length<=3*1024*1024 ? [[NSData alloc] initWithBase64EncodedString:encoded options:0]:nil;
                NSData *png=(image && images.count<16 && imageBytes<4*1024*1024) ? PFImage(image):nil;
                if(!png || png.length>4*1024*1024-imageBytes){[omissions addObject:[label stringByAppendingString:@"有图片输出不可读或超额"]];continue;}
                NSString *asset=[NSString stringWithFormat:@".notebook-output/%@/cell-%lu-output-%lu.png",AMPreflightHash([path dataUsingEncoding:NSUTF8StringEncoding]),(unsigned long)i+1,(unsigned long)outputIndex];
                append([NSString stringWithFormat:@"输出 %lu（图片，需另行确认）",(unsigned long)outputIndex]);
                images[asset]=@{@"path":asset,@"data":png,@"version":AMPreflightHash(png),@"image":@YES,@"notebookDocument":path,@"line":@(lines.count),@"cell":@(i+1)};
                imageBytes+=png.length;
            }else if(!plain.length && (bundle.count || output[@"output_type"]))[omissions addObject:[label stringByAppendingString:@"有不支持的输出格式"]];
        }
    }
    return @{@"text":[lines componentsJoinedByString:@"\n"],@"images":images,@"omissions":[NSOrderedSet orderedSetWithArray:omissions].array};
}
