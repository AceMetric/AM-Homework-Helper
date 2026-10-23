NSDictionary *DDLSeriesPatch(NSDictionary *original,NSDictionary *edited){
    NSMutableDictionary *patch=NSMutableDictionary.dictionary;for(NSString *key in @[@"title",@"subject",@"courseID",@"courseRepository",@"notes",@"priority",@"reminderOffsets",@"reminder"]){
        if(![(original[key] ?: NSNull.null) isEqual:edited[key] ?: NSNull.null])patch[key]=edited[key] ?: NSNull.null;}return patch;
}
static void AMApplySeriesPatch(NSMutableDictionary *row,NSDictionary *patch){for(NSString *key in patch)if(patch[key]==NSNull.null)[row removeObjectForKey:key];else row[key]=patch[key];}
NSString *DDLSeriesFamily(NSString *identifier,NSArray *series){for(NSDictionary *row in series)if([row[@"id"] isEqual:identifier])return row[@"familyID"] ?: identifier;return identifier ?: @"";}
NSDictionary *DDLSeriesEdit(NSArray *tasks,NSArray *series,NSDictionary *original,NSDictionary *edited,NSInteger scope,BOOL overwrite){
    NSDictionary *patch=DDLSeriesPatch(original,edited);NSString *family=DDLSeriesFamily(original[@"seriesID"],series);NSDate *boundary=original[@"nominalDue"] ?: original[@"due"];NSMutableArray *rows=NSMutableArray.array,*rules=NSMutableArray.array;NSMutableSet *affectedIDs=NSMutableSet.set;NSUInteger affected=0,skipped=0;
    for(NSDictionary *row in tasks){NSMutableDictionary *copy=row.mutableCopy;BOOL member=[DDLSeriesFamily(row[@"seriesID"],series) isEqual:family] && [row[@"seriesID"] length];BOOL selected=[row[@"id"] isEqual:original[@"id"]];
        if(member && ![row[@"deleted"] boolValue] && (selected || (scope>0 && (scope==2 || [(row[@"nominalDue"] ?: row[@"due"]) compare:boundary]!=NSOrderedAscending)))){
            NSMutableDictionary *effective=patch.mutableCopy;NSArray *exceptions=row[@"occurrenceOverrides"];if(!selected && !overwrite){for(NSString *key in patch)if([exceptions containsObject:key] || ([row[@"occurrenceEdited"] boolValue] && !exceptions)){[effective removeObjectForKey:key];skipped++;}}
            if(effective.count){AMApplySeriesPatch(copy,effective);affected++;[affectedIDs addObject:row[@"id"]];}if(scope==0 && selected){NSMutableSet *overrides=[NSMutableSet setWithArray:exceptions ?: @[]];[overrides addObjectsFromArray:patch.allKeys];copy[@"occurrenceOverrides"]=overrides.allObjects;copy[@"occurrenceEdited"]=@YES;}
        }[rows addObject:copy];
    }
    for(NSDictionary *seriesRow in series){NSMutableDictionary *copy=seriesRow.mutableCopy;if(scope>0 && [DDLSeriesFamily(copy[@"id"],series) isEqual:family] && patch.count){
            copy[@"familyID"]=family;NSMutableDictionary *template=[copy[@"template"] mutableCopy];NSMutableArray *changes=NSMutableArray.array;
            for(NSDictionary *change in copy[@"changes"] ?: @[]){NSMutableDictionary *p=[change[@"fields"] mutableCopy];if(scope==2)for(NSString *key in patch)[p removeObjectForKey:key];if(p.count)[changes addObject:@{@"from":change[@"from"],@"fields":p}];}
            if(scope==2)AMApplySeriesPatch(template,patch);else {NSMutableDictionary *serial=NSMutableDictionary.dictionary;for(NSString *key in patch)serial[key]=patch[key]==NSNull.null ? @"":patch[key];[changes addObject:@{@"from":boundary,@"fields":serial}];[changes sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"from"] compare:b[@"from"]];}];}copy[@"template"]=template;copy[@"changes"]=changes;
        }[rules addObject:copy];}
    return @{@"tasks":rows,@"series":rules,@"affected":@(affected),@"affectedIDs":affectedIDs.allObjects,@"skipped":@(skipped)};
}
