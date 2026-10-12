// Native review UI; the report never starts Git operations by itself.
static NSTextView *PFText(NSView *root,NSRect frame,BOOL editable){
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:frame];scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;
    NSTextView *text=[[PastelNotesView alloc] initWithFrame:NSMakeRect(0,0,frame.size.width-16,frame.size.height)];text.editable=editable;text.richText=NO;text.font=[NSFont systemFontOfSize:13];text.textColor=Ink();text.backgroundColor=Card();text.textContainerInset=NSMakeSize(8,8);text.autoresizingMask=NSViewWidthSizable;text.textContainer.widthTracksTextView=YES;scroll.documentView=text;[root addSubview:scroll];return text;
}
@interface PFImageView:NSView
@property NSImage *image;
@property NSArray *region;
@end
@implementation PFImageView
- (void)drawRect:(NSRect)dirty {
    [Card() setFill];NSRectFill(self.bounds);if(!self.image)return;
    NSSize size=self.image.size;CGFloat ratio=MIN(self.bounds.size.width/MAX(1,size.width),self.bounds.size.height/MAX(1,size.height));NSRect r=NSMakeRect((self.bounds.size.width-size.width*ratio)/2,(self.bounds.size.height-size.height*ratio)/2,size.width*ratio,size.height*ratio);
    [self.image drawInRect:r];if(self.region.count==4){NSRect highlight=NSMakeRect(r.origin.x+[self.region[0] doubleValue]*r.size.width,r.origin.y+(1-[self.region[1] doubleValue]-[self.region[3] doubleValue])*r.size.height,[self.region[2] doubleValue]*r.size.width,[self.region[3] doubleValue]*r.size.height);[NSColor.systemOrangeColor setStroke];NSBezierPath *path=[NSBezierPath bezierPathWithRect:highlight];path.lineWidth=3;[path stroke];}
}
@end
@interface PFMaterials:NSObject
@property NSMutableArray *images;
@property NSMutableSet *excluded;
@property NSDictionary *snapshot;
@property NSPopUpButton *picker;
@property NSButton *include;
@property PFImageView *image;
- (void)select:(id)sender;
@end
@implementation PFMaterials
- (void)select:(id)sender {NSInteger i=self.picker.indexOfSelectedItem;if(i<0 || i>=(NSInteger)self.images.count)return;NSDictionary *row=self.images[i];self.image.image=[[NSImage alloc] initWithData:self.snapshot[@"files"][row[@"path"]][@"data"]];self.image.region=nil;self.image.needsDisplay=YES;self.include.state=[self.excluded containsObject:row[@"path"]] ? NSControlStateValueOff:NSControlStateValueOn;}
- (void)toggle:(id)sender {NSInteger i=self.picker.indexOfSelectedItem;if(i<0)return;NSString *path=self.images[i][@"path"];if(self.include.state==NSControlStateValueOn)[self.excluded removeObject:path];else [self.excluded addObject:path];}
- (void)move:(NSButton *)sender {NSInteger i=self.picker.indexOfSelectedItem,j=i+sender.tag;if(j<0 || j>=(NSInteger)self.images.count)return;[self.images exchangeObjectAtIndex:i withObjectAtIndex:j];[self reload:j];}
- (void)reload:(NSInteger)index {[self.picker removeAllItems];for(NSDictionary *row in self.images)[self.picker addItemWithTitle:row[@"path"]];if(self.images.count)[self.picker selectItemAtIndex:MAX(0,index)];[self select:nil];}
@end
