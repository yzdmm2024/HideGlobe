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

// 地球键识别串（frida 会打印所有键的 representedString 供核对；必要时改这里）
static NSString *const HG_GLOBE_REP = @"globe";

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

// 递归遍历视图树：把 representedString 命中地球键的 UIKBKeyView 隐藏
static void hgHideGlobeInView(UIView *view) {
    if (!view) return;
    if ([view respondsToSelector:@selector(representedString)]) {
        id rs = [view performSelector:@selector(representedString)];
        if ([rs isKindOfClass:[NSString class]] &&
            [rs caseInsensitiveCompare:HG_GLOBE_REP] == NSOrderedSame) {
            [view setHidden:YES];
            [view setUserInteractionEnabled:NO];
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
