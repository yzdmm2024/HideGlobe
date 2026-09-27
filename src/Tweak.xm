// HideGlobe — 隐藏系统键盘地球（输入法切换）键
//
// 真相（已用 iOS 私有头 UIKeyboardLayoutStar / UIKBKeyView 核实）：
//   地球不是 UIKeyboardImpl 的独立按钮，而是 UIKeyboardLayoutStar keyplane 里一个
//   representedString == "globe" 的 UIKBKeyView 键。
//   我们在 layoutSubviews 后遍历所有键视图，命中 globe 键就隐藏它。
//   参考实现：DockX / TypeX 都用 [keyView representedString] 识别按键。
//
// 偏好文件：/var/jb/var/mobile/Library/Preferences/com.yzdmm.hideglobe.plist
// 与设置面板 Root.plist 的 defaults=com.yzdmm.hideglobe / key=enabled 对应
//
// 验证：跑 frida_hideglobe.js，先 dumpKeys() 确认 representedString 确为 "globe"
//       （若你的 iOS 版本串不同，改下方 HG_GLOBE_REP 即可）。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 私有类声明：14.5 SDK 不含这些头，自行声明用到的 API，否则编译器不认
// sharedInstance / layout，也不把 UIKeyboardLayoutStar 当作 UIView 子类。
@interface UIKeyboardImpl : NSObject
+ (instancetype)sharedInstance;
- (id)layout;
@end

@interface UIKeyboardLayoutStar : UIView
@end

#define HG_DARWIN_NOTI "com.yzdmm.hideglobe.prefschanged"

static BOOL hgEnabled = YES;

// 地球键识别串：
//   - representedString 可能是 "globe"（旧系统），或直接就是 🌐（iOS 16 实测常见）
//   - displayString 也可能是 🌐
// 三个条件任一命中即隐藏；都不中再考虑改这里。
static NSString *const HG_GLOBE_REP    = @"globe";
static NSString *const HG_GLOBE_EMOJI = @"\U0001F310"; // 🌐

static NSString *hgPrefsPath(void) {
    NSString *leaf = @"var/mobile/Library/Preferences/com.yzdmm.hideglobe.plist";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *p = [@"/var/jb" stringByAppendingPathComponent:leaf];
    if ([fm fileExistsAtPath:p]) return p;
    NSString *base = @"/private/var/containers/Bundle/Application";
    for (NSString *it in [fm contentsOfDirectoryAtPath:base error:nil]) {
        if ([it hasPrefix:@".jbroot-"]) {
            NSString *cand = [[base stringByAppendingPathComponent:it] stringByAppendingPathComponent:leaf];
            if ([fm fileExistsAtPath:cand]) return cand;
        }
    }
    return p;
}

static void hgLoadPrefs(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:hgPrefsPath()];
    id v = d ? d[@"enabled"] : nil;
    if (v == nil) hgEnabled = YES;
    else if ([v isKindOfClass:[NSNumber class]]) hgEnabled = [v boolValue];
    else if ([v isKindOfClass:[NSString class]]) hgEnabled = [(NSString *)v boolValue];
    else hgEnabled = YES;
}

// 取 displayString（地球键常在这里返回 🌐）
static NSString *hgDisplayString(UIView *view) {
    if ([view respondsToSelector:@selector(displayString)]) {
        id ds = [view performSelector:@selector(displayString)];
        if ([ds isKindOfClass:[NSString class]]) return ds;
    }
    return nil;
}

// 递归遍历视图树：把命中地球键的 UIKBKeyView 隐藏
static void hgHideGlobeInView(UIView *view) {
    if (!view) return;
    if ([view respondsToSelector:@selector(representedString)]) {
        id rs = [view performSelector:@selector(representedString)];
        NSString *rsStr = [rs isKindOfClass:[NSString class]] ? rs : nil;
        NSString *dsStr = hgDisplayString(view);
        BOOL match = NO;
        if (rsStr) {
            if ([rsStr caseInsensitiveCompare:HG_GLOBE_REP] == NSOrderedSame) match = YES;
            if ([rsStr isEqualToString:HG_GLOBE_EMOJI]) match = YES;
        }
        if (dsStr && [dsStr isEqualToString:HG_GLOBE_EMOJI]) match = YES;
        if (match) {
            [view setHidden:YES];
            [view setUserInteractionEnabled:NO];
            if ([view respondsToSelector:@selector(setAlpha:)]) [view setAlpha:0];
            NSLog(@"[HideGlobe] hid globe key rep=%@ disp=%@", rsStr, dsStr);
            return;
        }
    }
    for (UIView *sub in view.subviews) hgHideGlobeInView(sub);
}

// 设置改值后强制当前键盘重新布局，立即生效
static void hgRelayoutKeyboard(void) {
    UIKeyboardImpl *kb = [UIKeyboardImpl sharedInstance];
    if (!kb) return;
    id layout = [kb layout];
    if (layout && [layout respondsToSelector:@selector(setNeedsLayout)]) {
        [layout setNeedsLayout];
    }
}

%hook UIKeyboardLayoutStar

- (void)layoutSubviews {
    %orig;
    if (!hgEnabled) return;
    hgHideGlobeInView(self);
}

- (void)updateKeyCentroids {
    %orig;
    if (!hgEnabled) return;
    hgHideGlobeInView(self);
}

%end

static void hgPrefsChanged(CFNotificationCenterRef center, void *observer,
                           CFStringRef name, const void *object, CFDictionaryRef info) {
    hgLoadPrefs();
    hgRelayoutKeyboard();
}

%ctor {
    hgLoadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        NULL, hgPrefsChanged, CFSTR(HG_DARWIN_NOTI), NULL,
        CFNotificationSuspensionBehaviorCoalesce);
    NSLog(@"[HideGlobe] loaded, hide globe = %@", hgEnabled ? @"ON" : @"OFF");
}
