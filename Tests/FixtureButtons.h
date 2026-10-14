#ifndef AM_FIXTURE_BUTTONS_H
#define AM_FIXTURE_BUTTONS_H
// Isolated fixtures locate real native actions without production-only helpers.
static NSButton *AMFindButton(NSView *view,SEL action,NSInteger tag,NSString *identifier){
    if([view isKindOfClass:NSButton.class]){NSButton *button=(id)view;if(button.action==action && (identifier ? [button.identifier isEqual:identifier]:button.tag==tag))return button;}
    for(NSView *child in view.subviews){NSButton *match=AMFindButton(child,action,tag,identifier);if(match)return match;}return nil;
}
#endif
