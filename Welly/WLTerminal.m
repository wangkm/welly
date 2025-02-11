//
//  WLTerminal.m
//  Welly
//
//  YLTerminal.m
//  MacBlueTelnet
//
//  Created by Yung-Luen Lan on 2006/9/10.
//  Copyright 2006 yllan.org. All rights reserved.
//

#import "WLTerminal.h"
#import "WLGlobalConfig.h"
#import "WLConnection.h"
#import "WLSite.h"

const NSNotificationName WLTerminalBBSStateDidChangeNotification = @"WLTerminalBBSStateDidChangeNotification";

@interface WLTerminal ()
- (void)notifyObservers;
@end

@implementation WLTerminal {
    NSInteger _offset;
    BOOL **_dirty;
    NSMutableSet *_observers;
    unichar *_textBuf;
}

- (instancetype)init {
    if (self = [super init]) {
        _maxRow = [WLGlobalConfig sharedInstance].row;
        _maxColumn = [WLGlobalConfig sharedInstance].column;
        _grid = (cell **)malloc(sizeof(cell *) * _maxRow);
        _dirty = (BOOL **)malloc(sizeof(BOOL *) * _maxRow);
        int i;
        for (i = 0; i < _maxRow; i++) {
            // NOTE: in case _cursorX will exceed _column size (at the border of the
            //		 screen), we allocate one more unit for this array
            _grid[i] = (cell *)malloc(sizeof(cell) * (_maxColumn + 1));
            _dirty[i] = (BOOL *)malloc(sizeof(BOOL) * _maxColumn);
        }
        _textBuf = (unichar *)malloc(sizeof(unichar) * (_maxRow * _maxColumn + 1));
        
        _observers = [[NSMutableSet alloc] init];
        
        [self clearAll];
    }
    return self;
}

- (void)dealloc {
    for (NSInteger i = 0; i < _maxRow; i++) {
        free(_grid[i]);
        free(_dirty[i]);
    }
    free(_grid);
    free(_dirty);
    free(_textBuf);
    
}

#pragma mark -
#pragma mark input interface
- (void)feedGrid:(cell **)grid {
    // Clear the url list
    for (int i = 0; i < _maxRow; i++) {
        memcpy(_grid[i], grid[i], sizeof(cell) * (_maxColumn + 1));
    }
    
    for (int i = 0; i < _maxRow; i++) {
        [self updateDoubleByteStateForRow:i];
    }
    
    [self updateBBSState];
    
    [self notifyObservers];
    /*
     [_view performSelector:@selector(tick:)
     withObject:nil
     afterDelay:0.01];
     */
}

- (void)setCursorX:(NSInteger)cursorX
                 Y:(NSInteger)cursorY {
    _cursorColumn = cursorX;
    _cursorRow = cursorY;
}

# pragma mark -
# pragma mark Clear
- (void)clearAll {
    _cursorColumn = _cursorRow = 0;
    
    attribute t;
    t.f.fgColor = [WLGlobalConfig sharedInstance].fgColorIndex;
    t.f.bgColor = [WLGlobalConfig sharedInstance].bgColorIndex;
    t.f.bold = 0;
    t.f.underline = 0;
    t.f.blink = 0;
    t.f.reverse = 0;
    t.f.url = 0;
    t.f.nothing = 0;
    for (int i = 0; i < _maxRow; i++) {
        for (int j = 0; j < _maxColumn; j++) {
            _grid[i][j].byte = '\0';
            _grid[i][j].attr.v = t.v;
        }
    }
    
    [self setAllDirty];
}

# pragma mark -
# pragma mark Dirty
- (void)setAllDirty {
    for (int r = 0; r < _maxRow; r++)
    for (int c = 0; c < _maxColumn; c++)
    _dirty[r][c] = YES;
}

- (void)setDirtyForRow:(NSInteger)r {
    for (int c = 0; c < _maxColumn; c++)
    _dirty[r][c] = YES;
}

- (BOOL)isDirtyAtRow:(NSInteger)r
              column:(NSInteger)c {
    return _dirty[r][c];
}

- (void)setDirty:(BOOL)d
           atRow:(NSInteger)r
          column:(NSInteger)c {
    _dirty[r][c] = d;
}

- (void)removeAllDirtyMarks {
    for (int r = 0; r < _maxRow; ++r)
    memset(_dirty[r], 0, sizeof(BOOL) * _maxColumn);
}

# pragma mark -
# pragma mark Access Data
- (attribute)attrAtRow:(NSInteger)r
                column:(NSInteger)c {
    return _grid[r][c].attr;
}

- (NSString *)stringAtIndex:(NSInteger)begin
                     length:(NSInteger)length {
    NSInteger i, j;
    //unichar textBuf[length + 1];
    unichar firstByte = 0;
    NSInteger bufLength = 0;
    NSInteger spacebuf = 0;
    if (begin + length > _maxRow * _maxColumn) {
        length = _maxRow * _maxColumn - begin;
    }
    for (i = begin; i < begin + length; i++) {
        NSInteger x = i % _maxColumn;
        NSInteger y = i / _maxColumn;
        if (x == 0 && i != begin && i - 1 < begin + length) { // newline
            // REVIEW: why we need to update double byte state?????
            [self updateDoubleByteStateForRow:y];
            unichar cr = 0x000D;
            _textBuf[bufLength++] = cr;
            spacebuf = 0;
        }
        int db = _grid[y][x].attr.f.doubleByte;
        if (db == 0) {
            if (_grid[y][x].byte == '\0' || _grid[y][x].byte == ' ')
                spacebuf++;
            else {
                for (j = 0; j < spacebuf; j++)
                _textBuf[bufLength++] = ' ';
                _textBuf[bufLength++] = _grid[y][x].byte;
                spacebuf = 0;
            }
        } else if (db == 1) {
            firstByte = _grid[y][x].byte;
        } else if (db == 2 && firstByte) {
            int index = (firstByte << 8) + _grid[y][x].byte - 0x8000;
            for (j = 0; j < spacebuf; j++)
            _textBuf[bufLength++] = ' ';
            _textBuf[bufLength++] = [WLEncoder toUnicode:index encoding:self.connection.site.encoding];
            
            spacebuf = 0;
        }
    }
    if (bufLength == 0) return nil;
    return [NSString stringWithCharacters:_textBuf length:bufLength];
}

// Note that the 'length' means the number of characters in return string
// A Chinese character is counted as 1 character in return string
// Different from the method 'stringAtIndex:length'!!
- (NSAttributedString *)attributedStringAtIndex:(NSInteger)location
                                         length:(NSInteger)length {
    NSFont *englishFont = [NSFont fontWithName:[WLGlobalConfig sharedInstance].englishFontName 
                                          size:[WLGlobalConfig sharedInstance].englishFontSize];
    NSFont *chineseFont = [NSFont fontWithName:[WLGlobalConfig sharedInstance].chineseFontName
                                          size:[WLGlobalConfig sharedInstance].chineseFontSize];
    // Get twice length and then trim it to 'length' characters
    NSString *s = [[self stringAtIndex:location length:length*2] substringToIndex:length];
    
    NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] initWithString:s];
    // Set all characters with english font at first
    [attrStr addAttribute:NSFontAttributeName 
                    value:englishFont
                    range:NSMakeRange(0, attrStr.length)];
    // Fix the non-English characters' font
    [attrStr fixFontAttributeInRange:NSMakeRange(0, attrStr.length)];
    
    // Now replace all the fixed characters' font to be Chinese Font
    NSRange limitRange;
    NSRange effectiveRange;
    id attributeValue;
    
    limitRange = NSMakeRange(0, attrStr.length);
    
    while (limitRange.length > 0) {
        attributeValue = [attrStr attribute:NSFontAttributeName
                                    atIndex:limitRange.location 
                      longestEffectiveRange:&effectiveRange
                                    inRange:limitRange];
        if (![(NSFont *)attributeValue isEqual:englishFont]) {
            // Not the englishFont, which means that it is fixed
            [attrStr addAttribute:NSFontAttributeName 
                            value:chineseFont 
                            range:effectiveRange];
        }
        limitRange = NSMakeRange(NSMaxRange(effectiveRange),
                                 NSMaxRange(limitRange) - NSMaxRange(effectiveRange));
    }
    return attrStr;
}

- (NSString *)stringAtRow:(NSInteger)row {
    return [self stringAtIndex:row * _maxColumn length:_maxColumn];
}

- (cell *)cellsOfRow:(NSInteger)r {
    return _grid[r];
}

- (cell)cellAtIndex:(NSInteger)index {
    return _grid[index / _maxColumn][index % _maxColumn];
}

# pragma mark -
# pragma mark Update State
- (void)updateDoubleByteStateForRow:(NSInteger)r {
    cell *currRow = _grid[r];
    int db = 0;
    BOOL isDirty = NO;
    for (int c = 0; c < _maxColumn; c++) {
        if (db == 0 || db == 2) {
            if (currRow[c].byte > 0x7F) {
                db = 1;
                // Fix double bytes' dirty property ot be consistent
                if (c < _maxColumn) {
                    isDirty = _dirty[r][c] || _dirty[r][c+1];
                    _dirty[r][c] = isDirty;
                    _dirty[r][c+1] = isDirty;
                }
            }
            else db = 0;
        } else { // db == 1
            db = 2;
        }
        currRow[c].attr.f.doubleByte = db;
    }
}

//static NSString *extractString(NSString *row, NSString *start, NSString *end) {
//    NSRange rs = [row rangeOfString:start], re = [row rangeOfString:end];
//    if (rs.length == 0 || re.length == 0 || re.location <= rs.location)
//        return nil;
//    return [row substringWithRange:NSMakeRange(rs.location + 1, re.location - rs.location - 1)];    
//}

inline static BOOL hasAnyString(NSString *row, NSArray *array) {
    if (row == nil)
        return NO;
    NSString *s;
    for (s in array) {
        if ([row rangeOfString:s].length > 0)
            return YES;
    }
    return NO;
}

//
// added by K.O.ed
// WARNING: bunch of hard code
// 
- (void)updateBBSState {
    NSString *topLine = [self stringAtRow:0];	// get the first line from the screen
    NSString *secondLine = [self stringAtRow:1];
    NSString *thirdLine = [self stringAtRow:2];
    NSString *bottomLine = [self stringAtRow:_maxRow-1];
    NSString *wholePage = [self stringAtIndex:0 length:_maxRow * _maxColumn];
    _bbsState.subState = BBSSubStateNone;
    if (NO) {
        // just for align
    } else if (hasAnyString(bottomLine, @[@"朋友"])) {
        //NSLog(@"用户信息");
        _bbsState.state = BBSUserInfo;
    } else if (hasAnyString(bottomLine, @[@"【  】", @"【信】", @"編輯文章"])) {
        //NSLog(@"发表文章");
        _bbsState.state = BBSComposePost;
    } else if (hasAnyString(secondLine, @[@"目前"])
               || hasAnyString(topLine, @[@"主功能表", @"聊天說話", @"個人設定", @"工具程式", @"網路遊樂場", @"白色恐怖"])) {
        //NSLog(@"主选单");
        _bbsState.state = BBSMainMenu;
    } else if (hasAnyString(topLine, @[@"讨论区列表", @"个人定制区", @"我的讨论区", @"看板列表", @"板板列表"])) {
        //NSLog(@"讨论区列表");
        _bbsState.state = BBSBoardList;
    } else if (hasAnyString(topLine, @[@"好朋友列表", @"使用者列表"]) || hasAnyString(bottomLine, @[@"休閒聊天"])) {
        //NSLog(@"好朋友列表");
        _bbsState.state = BBSFriendList;
    } else if (hasAnyString(topLine, @[@"处理信笺选单", @"電子郵件"])) {
        //NSLog(@"处理信笺选单");
        _bbsState.state = BBSMailMenu;
    } else if (hasAnyString(topLine, @[@"邮件选单", @"郵件選單"])) {
        //NSLog(@"邮件选单");
        _bbsState.state = BBSMailList;
    } else if (hasAnyString(topLine, @[@"我的文章"])) {
        //NSLog(@"我的文章");
        _bbsState.state = BBSMentionList;
    } else if (hasAnyString(topLine, @[@"版主", @"板主", @"诚征版主中", @"徵求中"])) {
        //NSLog(@"版面");
        _bbsState.state = BBSBrowseBoard;
        // _bbsState.boardName = extractString(topLine, @"[", @"]");      // smth
        // if (_bbsState.boardName == nil)
        //     _bbsState.boardName = extractString(topLine, @"《", @"》"); // ptt
        if (hasAnyString(thirdLine, @[@"一般模式"]))
            _bbsState.subState = BBSBrowseBoardNormalMode;
        else if (hasAnyString(thirdLine, @[@"文摘模式"]))
            _bbsState.subState = BBSBrowseBoardDigestMode;
        else if (hasAnyString(thirdLine, @[@"主题模式"]))
            _bbsState.subState = BBSBrowseBoardThreadMode;
        else if (hasAnyString(thirdLine, @[@"精华模式"]))
            _bbsState.subState = BBSBrowseBoardMarkMode;
        else if (hasAnyString(thirdLine, @[@"原作模式"]))
            _bbsState.subState = BBSBrowseBoardOriginMode;
        else if (hasAnyString(thirdLine, @[@"作者模式"]))
            _bbsState.subState = BBSBrowseBoardAuthorMode;
        //NSLog(@"%@, cursor @ row %d", _bbsState.boardName, _bbsState.cursorRow);
    } else if (hasAnyString(bottomLine, @[@"阅读文章", @"主题阅读", @"同作者阅读", @"下面还有喔", @"瀏覽"])) {
        //NSLog(@"阅读文章");
        _bbsState.state = BBSViewPost;
    } else if (hasAnyString(bottomLine, @[@"[功能键]", @"[版  主]", @"【功能鍵】", @"【板  主】"])) {
        //NSLog(@"浏览精华区");
        _bbsState.state = BBSBrowseExcerption;
    } else if (hasAnyString(bottomLine, @[@"讯息浏览器"])) {
        //NSLog(@"讯息浏览器");
        _bbsState.state = BBSMessageList;
    } else if (hasAnyString(wholePage, @[@"按任意键继续", @"按回车键", @"按 [RETURN] 继续", @"按 ◆Enter◆ 继续", @"按 <ENTER> 继续", @"按任何键继续", @"上次连线时间为", @"按任意鍵繼續", @"請按空白鍵或是Enter繼續"])) {
        //NSLog(@"按回车继续");
        _bbsState.state = BBSWaitingEnter;
    } else if (hasAnyString(wholePage, @[@"請按 空白鍵 繼續"])) {
        //NSLog(@"按空白键继续");
        _bbsState.state = BBSWaitingSpace;
    } else {
        //NSLog(@"未知状态");
        _bbsState.state = BBSUnknown;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:WLTerminalBBSStateDidChangeNotification
                                                        object:self
                                                      userInfo:@{
                                                          @"bbsState" : [NSValue valueWithBytes:&_bbsState objCType:@encode(BBSState)]
                                                      }];
}

# pragma mark -
# pragma mark Accessor
- (WLEncoding)encoding {
    return self.connection.site.encoding;
}

- (void)setEncoding:(WLEncoding)encoding {
    self.connection.site.encoding = encoding;
}

- (void)setConnection:(WLConnection *)value {
    _connection = value;
    // FIXME: BBS type is temoprarily determined by the ansi color key.
    // remove #import "YLSite.h" when fixed.
    self.bbsType = _connection.site.encoding == WLBig5Encoding ? WLMaple : WLFirebird;
}

#pragma mark -
#pragma mark Observe subject
- (void)addObserver:(id <WLTerminalObserver>)observer {
    [_observers addObject:observer];
}

- (void)notifyObservers {
    for (id <WLTerminalObserver> observer in _observers) {
        [observer terminalDidUpdate:self];
    }
}
@end
