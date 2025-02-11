//
//  WLClickEntryHotspotHandler.m
//  Welly
//
//  Created by K.O.ed on 09-1-12.
//  Copyright 2009 Welly Group. All rights reserved.
//

#import "WLClickEntryHotspotHandler.h"
#import "WLMouseBehaviorManager.h"
#import "WLEffectView.h"
#import "WLGlobalConfig.h"
#import "WLMainFrameController.h"
#import "WLTerminal.h"
#import "WLTerminalView.h"
#import "WLConnection.h"
#import "WLEncoder.h"
#import "WLPostDownloadDelegate.h"

NSString *const WLMenuTitleDownloadPost = @"Download post";
NSString *const WLMenuTitleThreadTop = @"Thread top";
NSString *const WLMenuTitleThreadBottom = @"Thread bottom";
NSString *const WLMenuTitleSameAuthorReading = @"Same author reading";
NSString *const WLMenuTitleSameThreadReading = @"Same thread reading";

NSString *const WLCommandSequenceThreadTop = @"=";
NSString *const WLCommandSequenceThreadBottom = @"\\";
NSString *const FBCommandSequenceSameThreadReading = @"\030";	// ^X
NSString *const FBCommandSequenceSameAuthorReading = @"\025";	// ^U
NSString *const MPCommandSequenceSameThreadReading = @"S";

@implementation WLClickEntryHotspotHandler

#pragma mark -
#pragma mark Mouse Event Handler
- (void)moveCursorToRow:(int)moveToRow {
    unsigned char cmd[_maxRow * _maxColumn + 1];
    unsigned int cmdLength = 0;
    WLTerminal *ds = _view.frontMostTerminal;
    NSInteger cursorRow = ds.cursorRow;
    
    // Moving Command
    if (moveToRow > cursorRow) {
        for (NSInteger i = cursorRow; i < moveToRow; i++) {
            cmd[cmdLength++] = 0x1B;
            cmd[cmdLength++] = 0x4F;
            cmd[cmdLength++] = 0x42;
        }
    } else if (moveToRow < cursorRow) {
        for (NSInteger i = cursorRow; i > moveToRow; i--) {
            cmd[cmdLength++] = 0x1B;
            cmd[cmdLength++] = 0x4F;
            cmd[cmdLength++] = 0x41;
        }
    }
    
    [_view.frontMostConnection sendBytes:cmd length:cmdLength];
}

- (void)enterEntryAtRow:(int)moveToRow {
    [self moveCursorToRow:moveToRow];
    
    // Enter
    [_view sendText:termKeyEnter];
}

- (void)mouseUp:(NSEvent *)theEvent {
    NSString *commandSequence = (_manager.activeTrackingAreaUserInfo)[WLMouseCommandSequenceUserInfoName];
    if (commandSequence != nil) {
        [_view sendText:commandSequence];
        return;
    }
    int moveToRow = [(_manager.activeTrackingAreaUserInfo)[WLMouseRowUserInfoName] intValue];
    
    [self enterEntryAtRow:moveToRow];
}

- (void)mouseEntered:(NSEvent *)theEvent {
    _manager.activeTrackingAreaUserInfo = theEvent.trackingArea.userInfo;
    if (_view.isMouseActive) {
        [_view.effectView drawClickEntry:theEvent.trackingArea.rect];
    }
    [[NSCursor pointingHandCursor] set];
}

- (void)mouseExited:(NSEvent *)theEvent {
    [_view.effectView clearClickEntry];
    _manager.activeTrackingAreaUserInfo = nil;
    // FIXME: Temporally solve the problem in full screen mode.
    if ([NSCursor currentCursor] == [NSCursor pointingHandCursor])
        [_manager restoreNormalCursor];
}

- (void)mouseMoved:(NSEvent *)theEvent {
    if ([NSCursor currentCursor] != [NSCursor pointingHandCursor])
        [[NSCursor pointingHandCursor] set];
}

#pragma mark -
#pragma mark Contextual Menu
- (void)doDownloadPost:(id)sender {
    NSDictionary *userInfo = [sender representedObject];
    
    // Enter the entry
    int moveToRow = [userInfo[WLMouseRowUserInfoName] intValue];
    [self enterEntryAtRow:moveToRow];
    
    // Wait until state change
    const int sleepTime = 100000, maxAttempt = 300000;
    int count = 0;
    while (_view.frontMostTerminal.bbsState.state != BBSViewPost && count < maxAttempt) {
        ++count;
        usleep(sleepTime);
    }
    
    // Do Post Download
    if (count != maxAttempt) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[WLPostDownloadDelegate sharedInstance] beginPostDownloadInWindow:NSApp.keyWindow
                                                                   forTerminal:self->_view.frontMostTerminal];
        });
    }
}

- (IBAction)downloadPost:(id)sender {
    // Do this in new thread to avoid blocking the main thread
    [NSThread detachNewThreadSelector:@selector(doDownloadPost:) toTarget:self withObject:sender];
}

- (void)moveCursorBySender:(id)sender {
    NSDictionary *userInfo = [sender representedObject];
    
    // Move the cursor to the entry
    int moveToRow = [userInfo[WLMouseRowUserInfoName] intValue];
    [self moveCursorToRow:moveToRow];
}

- (IBAction)threadTop:(id)sender {
    [self moveCursorBySender:sender];
    [_view sendText:WLCommandSequenceThreadTop];
}

- (IBAction)threadBottom:(id)sender {
    [self moveCursorBySender:sender];
    [_view sendText:WLCommandSequenceThreadBottom];
}

- (IBAction)sameAuthorReading:(id)sender {
    [self moveCursorBySender:sender];
    NSString *commandSequence = nil;
    switch (_view.frontMostTerminal.bbsType) {
        case WLFirebird:
            commandSequence = FBCommandSequenceSameAuthorReading;
            break;
        case WLMaple:
            // Maple doesn't support same author reading
            return;
        default:
            return;
    }
    [_view sendText:commandSequence];
}

- (IBAction)sameThreadReading:(id)sender {
    [self moveCursorBySender:sender];
    NSString *commandSequence = nil;
    switch (_view.frontMostTerminal.bbsType) {
        case WLFirebird:
            commandSequence = FBCommandSequenceSameThreadReading;
            break;
        case WLMaple:
            commandSequence = MPCommandSequenceSameThreadReading;
            break;
        default:
            return;
    }
    [_view sendText:commandSequence];
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent {
    NSMenu *menu = [[NSMenu alloc] init];
    if (_view.frontMostTerminal.bbsState.state == BBSBrowseBoard) {
        [menu addItemWithTitle:NSLocalizedString(WLMenuTitleDownloadPost, @"Contextual Menu")
                        action:@selector(downloadPost:)
                 keyEquivalent:@""];
        [menu addItemWithTitle:NSLocalizedString(WLMenuTitleThreadTop, @"Contextual Menu")
                        action:@selector(threadTop:)
                 keyEquivalent:@""];
        [menu addItemWithTitle:NSLocalizedString(WLMenuTitleThreadBottom, @"Contextual Menu")
                        action:@selector(threadBottom:)
                 keyEquivalent:@""];
        [menu addItemWithTitle:NSLocalizedString(WLMenuTitleSameThreadReading, @"Contextual Menu")
                        action:@selector(sameThreadReading:)
                 keyEquivalent:@""];
        if (_view.frontMostTerminal.bbsType == WLFirebird) {
            [menu addItemWithTitle:NSLocalizedString(WLMenuTitleSameAuthorReading, @"Contextual Menu")
                            action:@selector(sameAuthorReading:)
                     keyEquivalent:@""];
        }
    }
    
    for (NSMenuItem *item in menu.itemArray) {
        if (item.separatorItem)
            continue;
        item.target = self;
        item.representedObject = _manager.activeTrackingAreaUserInfo;
    }
    return menu;
}

#pragma mark -
#pragma mark Add Tracking Areas
- (void)addClickEntryRect:(NSString *)title
                      row:(NSInteger)r
                   column:(NSInteger)c
                   length:(NSInteger)length {
    NSRect rect = [_view rectAtRow:r column:c height:1 width:length];
    // Generate User Info
    NSArray *keys = @[WLMouseHandlerUserInfoName, WLMouseRowUserInfoName];
    NSArray *objects = @[self, @(r)];
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjects:objects forKeys:keys];
    [_trackingAreas addObject:[_manager addTrackingAreaWithRect:rect userInfo:userInfo]];
}

- (void)addClickEntryRectAtRow:(NSInteger)r column:(NSInteger)c length:(NSInteger)length {
    NSString *title = [_view.frontMostTerminal stringAtIndex:c+r*_maxColumn length:length];
    [self addClickEntryRect:title row:r column:c length:length];
}

- (void)addMainMenuClickEntry:(NSString *)cmd 
                          row:(NSInteger)r
                       column:(NSInteger)c
                       length:(NSInteger)len {
    NSRect rect = [_view rectAtRow:r column:c height:1 width:len];
    // Generate User Info
    NSArray *keys = @[WLMouseHandlerUserInfoName, WLMouseCommandSequenceUserInfoName];
    NSArray *objects = @[self, cmd];
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjects:objects forKeys:keys];
    [_trackingAreas addObject:[_manager addTrackingAreaWithRect:rect userInfo:userInfo]];
}

#pragma mark -
#pragma mark Update State
- (BOOL)startsAtRow:(int)row 
             column:(int)column
               with:(NSString *)s {
    cell *currRow = [_view.frontMostTerminal cellsOfRow:row];
    NSInteger i = 0, n = s.length;
    for (; i < n && column < _maxColumn - 1; ++i, ++column)
    if (currRow[column].byte != [s characterAtIndex:i])
        return NO;
    if (i != n)
        return NO;
    return YES;
}

BOOL isPostTitleStarter(unichar c) {
    // smth: 0x25cf (black circle "●"), 0x251c ("├"), 0x2514 ("└"), 0x2605("★")
    // free/sjtu: 0x25c6 (black diamond "◆")
    // ptt: 0x25a1 (white square "□"), 0x25c7 (white diamond "◇")
    return (c == 0x25cf || c == 0x251c || c == 0x2514 || c == 0x2605
            || c == 0x25c6 || c == 0x25a1 || c == 0x25c7);
}

- (void)updatePostClickEntry {
    WLTerminal *ds = _view.frontMostTerminal;
    for (int r = 3; r < _maxRow - 1; ++r) {
        cell *currRow = [ds cellsOfRow:r];
        
        int start = -1, end = -1;
        unichar textBuf[_maxColumn + 1];
        int bufLength = 0;
        
        // don't check the first two columns ("●" may be used as cursor)
        for (int i = 2; i < _maxColumn; ++i) {
            // Skip rows with background color (e.g., in preview mode)
            if (currRow[i].attr.f.bgColor != 9)
                continue;
            
            int db = currRow[i].attr.f.doubleByte;
            if (db == 0) {
                if (start == -1) {
                    if ([self startsAtRow:r column:i with:@"Re:"] || // smth
                        [self startsAtRow:r column:i with:@"R: "])    // ptt
                        start = i;
                }
                if (currRow[i].byte > 0 && currRow[i].byte != ' ')
                    end = i;
                if (start != -1)
                    textBuf[bufLength++] = 0x0000 + (currRow[i].byte ?: ' ');
            } else if (db == 2) {
                unsigned short code = (((currRow + i - 1)->byte) << 8) + ((currRow + i)->byte) - 0x8000;
                unichar ch = [WLEncoder toUnicode:code encoding:(_view.frontMostConnection.site).encoding];
                // smth: 0x25cf (black circle "●"), 0x251c ("├"), 0x2514 ("└"), 0x2605("★")
                // free/sjtu: 0x25c6 (black diamond "◆")
                // ptt: 0x25a1 (white square "□"), 0x25c7 (white diamond "◇")
                if (start == -1 && isPostTitleStarter(ch))//ch >= 0x2510 && ch <= 0x260f)
                    start = i - 1;
                end = i;
                if (start != -1)
                    textBuf[bufLength++] = ch;
            }
        }
        
        if (start == -1)
            continue;
        
        [self addClickEntryRect:[NSString stringWithCharacters:textBuf length:bufLength]
                            row:r
                         column:start
                         length:((end - start + 1) > 30) ? (end - start + 1) : 30];
    }
}

- (void)updateBoardClickEntry {
    WLTerminal *ds = _view.frontMostTerminal;
    for (int r = 3; r < _maxRow - 1; ++r) {
        cell *currRow = [ds cellsOfRow:r];
        
        // TODO: fix magic numbers
        if (currRow[12].byte != 0 && currRow[12].byte != ' ' && (currRow[11].byte == ' ' || currRow[11].byte == '*'))
            [self addClickEntryRectAtRow:r column:12 length:80-29]; // smth
        else if (currRow[13].byte != 0 && currRow[13].byte != ' ' && (currRow[12].byte == ' ' || currRow[12].byte == '*'))
            [self addClickEntryRectAtRow:r column:13 length:80-29]; // smth overflow
        else if (currRow[10].byte != 0 && currRow[10].byte != ' ' && currRow[7].byte == ' ' && currRow[27].byte == ' ')
            [self addClickEntryRectAtRow:r column:10 length:80-26]; // ptt
        else if (currRow[10].byte != 0 && currRow[10].byte != ' ' && (currRow[9].byte == ' ' || currRow[9].byte == '-') && currRow[30].byte == ' ')
            [self addClickEntryRectAtRow:r column:10 length:80-23]; // lqqm
        else if (currRow[10].byte != 0 && (currRow[9].byte == ' ' || currRow[9].byte == '-') && currRow[31].byte == ' ')
            [self addClickEntryRectAtRow:r column:10 length:80-30]; // zju88
        else if (currRow[11].byte != 0 && currRow[11].byte != ' ' && (currRow[10].byte == ' ' || currRow[10].byte == '*') && currRow[37].byte == ' ')
            [self addClickEntryRectAtRow:r column:11 length:80-33]; // fudan
        else if (currRow[10].byte != 0 && currRow[10].byte != ' ' && (currRow[9].byte == ' ' || currRow[9].byte == '-') && currRow[35].byte == ' ')
            [self addClickEntryRectAtRow:r column:10 length:80-29]; // nankai
        else if (currRow[8].byte != 0 && currRow[8].byte != ' ' && currRow[7].byte == ' ' && currRow[33].byte == ' ')
            [self addClickEntryRectAtRow:r column:8 length:80-24]; // tku
        else if (currRow[8].byte != 0 && currRow[8].byte != ' ' && (currRow[5].byte == ' ' || currRow[5].byte == '-') && currRow[25].byte == ' ')
            [self addClickEntryRectAtRow:r column:8 length:80-26]; // wdbbs
        else if (currRow[8].byte != 0 && currRow[8].byte != ' ' && currRow[7].byte == ' ' && currRow[20].byte == ' ')
            [self addClickEntryRectAtRow:r column:8 length:80-36]; // cia
    }
}

- (void)updateFriendClickEntry {
    WLTerminal *ds = _view.frontMostTerminal;
    for (int r = 3; r < _maxRow - 1; ++r) {
        cell *currRow = [ds cellsOfRow:r];
        
        // TODO: fix magic numbers
        if (currRow[7].byte == 0 || currRow[7].byte == ' ')
            continue;
        [self addClickEntryRectAtRow:r column:7 length:80-13];
    }
}

- (void)updateMenuClickEntry {
    WLTerminal *ds = _view.frontMostTerminal;
    for (int r = 3; r < _maxRow - 1; ++r) {
        cell *currRow = [ds cellsOfRow:r];
        
        enum {
            ST_START, ST_BRACKET_FOUND, ST_SPACE_FOUND, ST_NON_SPACE_FOUND, ST_SINGLE_SPACE_FOUND
        };
        
        int start = -1, end = -1;
        int state = ST_START;
        char shortcut = 0;
        
        // don't check the first two columns ("●" may be used as cursor)
        for (int i = 2; i < _maxColumn - 2; ++i) {
            int db = currRow[i].attr.f.doubleByte;
            switch (state) {
                case ST_START:
                    if (currRow[i].byte == ')' && isalnum(currRow[i-1].byte)) {
                        start = (currRow[i-2].byte == '(')? i-2: i-1;
                        end = start;
                        state = ST_BRACKET_FOUND;
                        shortcut = currRow[i-1].byte;
                    }
                    break;
                case ST_BRACKET_FOUND:
                    end = i;
                    if (db == 1) {
                        state = ST_NON_SPACE_FOUND;
                    }
                    break;
                case ST_NON_SPACE_FOUND:
                    if (currRow[i].byte == ' ' || currRow[i].byte == 0) {
                        state = ST_SINGLE_SPACE_FOUND;
                    } else {
                        end = i;
                    }
                    break;
                case ST_SINGLE_SPACE_FOUND:
                    if (currRow[i].byte == ' ' || currRow[i].byte == 0) {
                        state = ST_START;
                        [self addMainMenuClickEntry:[NSString stringWithFormat:@"%c\n", shortcut]
                                                row:r
                                             column:start
                                             length:end - start + 1];
                        start = i;
                        end = i;
                    } else {
                        state = ST_NON_SPACE_FOUND;
                        end = i;
                    }
                    break;
                default:
                    break;
            }
        }
    }
}

- (void)updateExcerptionClickEntry {
    WLTerminal *ds = _view.frontMostTerminal;
    NSString *start = nil;
    NSString *end = nil;
    int header = 0;
    switch (ds.bbsType) {
        case WLFirebird:
            start = @"标";
            end = @"整";
            header = 2;
            break;
        case WLMaple:
            start = @"標";
            end = @"編";
            header = 1;
            break;
        default:
            return;
    }
    // Parse the table title line to get ranges
    NSRange postRange = {0, 0};
    int c = 0;
    for (; c < _maxColumn - 2; ++c) {
        if ([[ds stringAtIndex:c + header * _maxColumn length:2] isEqualToString:start]) {
            postRange.location = c;
            c += 2;
            break;
        }
    }
    for (; c < _maxColumn - 2; ++c) {
        if ([[ds stringAtIndex:c + header * _maxColumn length:2] isEqualToString:end]) {
            postRange.length = c - postRange.location - 1;
            break;
        }
    }
    
    // Parse each line
    for (int r = header + 1; r < _maxRow - 1; ++r) {
        cell *currRow = [ds cellsOfRow:r];
        
        for (NSInteger c = postRange.location; c < postRange.location + postRange.length; ++c)
        if (currRow[c].byte != 0 && currRow[c].byte != ' ') {
            [self addClickEntryRectAtRow:r column:postRange.location length:postRange.length];
            break;
        }
    }
}

- (BOOL)shouldUpdate {
    if (!_view.shouldEnableMouse || !_view.connected) {
        return YES;
    }
    
    // In the same page, do NOT update/clear
    WLTerminal *ds = _view.frontMostTerminal;
    BBSState bbsState = ds.bbsState;
    if (bbsState.state == _manager.lastBBSState.state && labs(_manager.lastCursorRow - ds.cursorRow) == 1) {
        return NO;
    }
    return YES;
}

- (void)update {
    // Clear
    [self clear];
    if (!_view.shouldEnableMouse || !_view.connected) {
        return;
    }
    
    // Update
    WLTerminal *ds = _view.frontMostTerminal;
    if (ds.bbsState.state == BBSBrowseBoard || ds.bbsState.state == BBSMailList || ds.bbsState.state == BBSMentionList) {
        [self updatePostClickEntry];
    } else if (ds.bbsState.state == BBSBoardList) {
        [self updateBoardClickEntry];
    } else if (ds.bbsState.state == BBSFriendList) {
        [self updateFriendClickEntry];
    } else if (ds.bbsState.state == BBSMainMenu || ds.bbsState.state == BBSMailMenu) {
        [self updateMenuClickEntry];
    } else if (ds.bbsState.state == BBSBrowseExcerption) {
        [self updateExcerptionClickEntry];
    }
}
@end
