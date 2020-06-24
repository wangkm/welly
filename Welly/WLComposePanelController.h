//
//  TYComposeDelegate.h
//  Welly
//
//  Created by aqua9 on 17/1/2009.
//  Copyright 2009 TANG Yang. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface WLComposePanelController : NSObject {
    NSView <NSTextInputClient> *_telnetView;
    
    IBOutlet NSColorWell *_bgColorWell;
    
    /* composeWindow */
    IBOutlet NSTextView *_composeText;
    IBOutlet NSPanel *_composePanel;
    
    NSShadow *_shadowForBlink;
}

+ (WLComposePanelController *)sharedInstance;

/* compose actions */
- (void)openComposePanelInWindow:(NSWindow *)window 
                         forView:(NSView <NSTextInputClient> *)telnetView;
- (IBAction)commitCompose:(id)sender;
- (IBAction)cancelCompose:(id)sender;
- (IBAction)setUnderline:(id)sender;
- (IBAction)setBlink:(id)sender;
- (IBAction)changeBackgroundColor:(id)sender;
- (void)clearAll;
@end
