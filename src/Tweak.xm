// HideGlobe Tweak.xm
// 隐藏系统键盘 dock（UIKeyboardDockView）里最左侧的输入法切换键（地球/globe）
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 14.5 SDK 缺私有框架头，自行声明私有类
@interface UIKeyboardDockView : UIView
@end
@interface UIKeyboardDockItemButton : UIButton
@end

// 地球键（切换输入法）由 UIKit 绘制在【键盘扩展进程】内，不是宿主 App 进程。
// 官方开关：UIInputViewController.needsInputModeSwitchKey，默认 YES。
// 腾讯微信输入法(wxkb / com.tencent.wetype)没关它，所以左下角一直有地球。

#define HG_DARWIN_NOTI "com.yzdmm.hideglobe.prefschanged"
static BOOL hgEnabled = YES;

// 直读 jbroot plist（绕过 cfprefsd 同步延迟，设置开关即时生效）
static NSString *hgPrefsPath(void) {
    return @"/var/jb/var/mobile/Library/Preferences/com.yzdmm.hideglobe.plist";
}
static void hgLoadPrefs(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:hgPrefsPath()];
    if (d) {
        id v = [d objectForKey:@"enabled"];
        if (v) hgEnabled = [v boolValue];
    }
}

// 尽力取出 UIImageView 的图片资源名
static NSString *hgImageName(UIView *v) {
    if ([v isKindOfClass:[UIImageView class]]) {
        UIImage *img = [(UIImageView *)v image];
        if (img) {
            id nm = [img valueForKey:@"_imageName"];
            if (nm) return [nm description];
            return [img description];
        }
    }
    return nil;
}

// 隐藏 dock 里的地球键：优先图片名含 globe，兜底最左侧按钮
static void hgHideGlobeInDock(UIView *dock) {
    if (!dock || !hgEnabled) return;
    Class btnCls = objc_getClass("UIKeyboardDockItemButton");
    if (!btnCls) return;

    NSMutableArray *items = [NSMutableArray array];
    for (UIView *sub in dock.subviews) {
        if ([sub isKindOfClass:btnCls]) [items addObject:sub];
    }
    if (items.count == 0) return;

    UIView *target = nil;
    // 1) 图片名含 globe / 地球
    for (UIView *it in items) {
        for (UIView *s2 in it.subviews) {
            NSString *nm = hgImageName(s2);
            if (nm && ([nm rangeOfString:@"globe" options:NSCaseInsensitiveSearch].location != NSNotFound
                       || [nm rangeOfString:@"地球" options:NSCaseInsensitiveSearch].location != NSNotFound)) {
                target = it; break;
            }
        }
        if (target) break;
    }
    // 2) 兜底：最左侧按钮（地球在 dock 中永远最左）
    if (!target) {
        UIView *leftmost = nil;
        CGFloat minX = CGFLOAT_MAX;
        for (UIView *it in items) {
            CGFloat x = it.frame.origin.x;
            if (x < minX) { minX = x; leftmost = it; }
        }
        target = leftmost;
    }
    if (target) {
        [target setHidden:YES];
        [target setUserInteractionEnabled:NO];
        [target setAlpha:0.0];
        NSLog(@"[HideGlobe] hid globe button (hidden=%d)", (int)hgEnabled);
    }
}

%hook UIKeyboardDockView
- (void)layoutSubviews {
    %orig;
    hgHideGlobeInDock(self);
}
%end

// needsInputModeSwitchKey 在头文件里是 readonly，setter 只存在于运行时，
// 直接写 [self setNeedsInputModeSwitchKey:NO] 编译不过，用 NSInvocation 绕过。
static void hgForceSwitchKeyOff(id vc) {
    if (!vc) return;
    SEL sel = NSSelectorFromString(@"setNeedsInputModeSwitchKey:");
    if (![vc respondsToSelector:sel]) return;
    NSMethodSignature *sig = [vc methodSignatureForSelector:sel];
    if (!sig) return;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setSelector:sel];
    BOOL no = NO;
    [inv setArgument:&no atIndex:2];
    [inv invokeWithTarget:vc];
}

// ===== 主方案：关掉苹果官方的「显示切换输入法键」开关 =====
%hook UIInputViewController
- (BOOL)needsInputModeSwitchKey {
    if (hgEnabled) return NO;
    return %orig;
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (hgEnabled) {
        hgForceSwitchKeyOff(self);
        [self.view setNeedsLayout];
    }
}
%end

// 设置开关变化：重新布局键盘窗口
static void hgPrefsChanged(CFNotificationCenterRef center, void *observer,
                           CFStringRef name, const void *object, CFDictionaryRef info) {
    hgLoadPrefs();
    NSArray *wins = [UIApplication sharedApplication].windows;
    for (UIWindow *w in wins) {
        NSString *cn = NSStringFromClass([w class]);
        if ([cn containsString:@"TextEffects"] || [cn containsString:@"Keyboard"]) {
            [w setNeedsLayout];
            break;
        }
    }
}

%ctor {
    hgLoadPrefs();
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL, hgPrefsChanged,
        CFSTR(HG_DARWIN_NOTI), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
    NSLog(@"[HideGlobe] loaded, hide globe = %@", hgEnabled ? @"ON" : @"OFF");
}
