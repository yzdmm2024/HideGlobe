// HideGlobe Tweak.xm (1.0.6)
// 隐藏系统/第三方键盘里的地球（输入法切换）键与 dock 内的 globe 按钮。
// 1.0.6：最低系统从 16.0 下调到 15.0（UIKeyboardDockView 自 iOS 11 就存在，挂载点通用），
//        支持 iOS 15.x 设备（如 iPhone 13 Pro Max 15.7.1）。
// 修复点：
//   1) 偏好路径兼容 RootHide（/var/jb 不存在，真实 jbroot 是 .jbroot-XXXX）
//   2) 注入到所有加载 UIKit 的进程（Filter -> Bundles: com.apple.UIKit），
//      覆盖系统键盘（宿主 App 进程）与第三方键盘扩展进程
//   3) globe 按位置隐藏：dock 最左 UIKeyboardDockItemButton（x 最小）即 globe；
//      不依赖 imageName/representedString（实测为空），不递归进按钮子视图（会崩）
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface UIKeyboardDockView : UIView
@end
@interface UIKeyboardDockItemButton : UIButton
@end
@interface UIKeyboardImpl : UIView
@end

#define HG_DARWIN_NOTI "com.yzdmm.hideglobe.prefschanged"
static BOOL hgEnabled = YES;

// jbroot 兼容：RootHide/roothide-compat 没有 /var/jb，真实 jbroot 是 .jbroot-XXXX
static NSString *hgPrefsPath(void) {
    NSString *leaf = @"var/mobile/Library/Preferences/com.yzdmm.hideglobe.plist";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *cands = [NSMutableArray array];
    [cands addObject:[@"/var/jb" stringByAppendingPathComponent:leaf]];
    // 扫描 /private/var/containers/Bundle/Application 下的 .jbroot-* 随机目录
    NSString *base = @"/private/var/containers/Bundle/Application";
    for (NSString *it in [fm contentsOfDirectoryAtPath:base error:nil]) {
        if ([it hasPrefix:@".jbroot-"]) {
            [cands addObject:[[base stringByAppendingPathComponent:it] stringByAppendingPathComponent:leaf]];
        }
    }
    for (NSString *p in cands) {
        if ([fm fileExistsAtPath:p]) return p;
    }
    return [cands firstObject];
}

static void hgLoadPrefs(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:hgPrefsPath()];
    if (d) {
        id v = [d objectForKey:@"enabled"];
        if (v) hgEnabled = [v boolValue];
    }
}

// 在 dock 内隐藏最左的 dock item 按钮（=globe）。
// 关键事实（已 frida 真机验证）：
//   - 地球键在 dock 中始终排在最左（x 最小），不能靠 imageName/representedString 判定
//     （实测所有 dock item 的 representedString 都是空，图在按钮内部 remote view 上）；
//   - 不能递归进按钮子视图（会踩键盘 remote view，注入后原生崩溃）。
// 所以只取 dock 的直接子视图，按 x 最小（兜底取第一个）定位 globe 并隐藏。
static void hgHideLeftmostDockItem(UIView *dock, BOOL hide) {
    Class btnCls = objc_getClass("UIKeyboardDockItemButton");
    if (!btnCls) return;
    UIView *leftmost = nil;
    CGFloat minX = CGFLOAT_MAX;
    for (UIView *sub in dock.subviews) {
        if ([sub isKindOfClass:btnCls]) {
            CGFloat x = CGRectGetMinX(sub.frame);
            if (x < minX) { minX = x; leftmost = sub; }
        }
    }
    if (!leftmost) {
        // 兜底：取 dock 中第一个 dock item 按钮（globe 通常排在最前）
        for (UIView *sub in dock.subviews)
            if ([sub isKindOfClass:btnCls]) { leftmost = sub; break; }
    }
    if (leftmost) {
        leftmost.hidden = hide;
        leftmost.userInteractionEnabled = !hide;
        leftmost.alpha = hide ? 0.0 : 1.0;
    }
}

// 在 root 里找所有 UIKeyboardDockView 并隐藏最左按钮（native 递归安全）
static void hgHideGlobeInRoot(UIView *root, BOOL hide) {
    if (!root || !hgEnabled) return;
    Class dockCls = objc_getClass("UIKeyboardDockView");
    if (!dockCls) return;
    if ([root isKindOfClass:dockCls]) { hgHideLeftmostDockItem(root, hide); return; }
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:dockCls]) hgHideLeftmostDockItem(sub, hide);
        else hgHideGlobeInRoot(sub, hide);
    }
}

%hook UIKeyboardDockView
- (void)layoutSubviews {
    %orig;
    hgHideGlobeInRoot(self, YES);
}
%end

%hook UIKeyboardImpl
- (void)layoutSubviews {
    %orig;
    hgHideGlobeInRoot(self, YES);
}
%end

// 第三方键盘：官方「显示切换输入法键」开关
%hook UIInputViewController
- (BOOL)needsInputModeSwitchKey {
    if (hgEnabled) return NO;
    return %orig;
}
- (void)viewDidLayoutSubviews {
    %orig;
    if (hgEnabled) {
        SEL sel = NSSelectorFromString(@"setNeedsInputModeSwitchKey:");
        if ([self respondsToSelector:sel]) {
            NSMethodSignature *sig = [self methodSignatureForSelector:sel];
            if (sig) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setSelector:sel];
                BOOL no = NO;
                [inv setArgument:&no atIndex:2];
                [inv invokeWithTarget:self];
            }
        }
    }
}
%end

// 设置开关变化：重新加载偏好 + 重排键盘窗口
static void hgPrefsChanged(CFNotificationCenterRef center, void *observer,
                           CFStringRef name, const void *object, CFDictionaryRef info) {
    hgLoadPrefs();
    UIApplication *app = [UIApplication sharedApplication];
    for (UIWindow *w in app.windows) {
        NSString *cn = NSStringFromClass([w class]);
        if ([cn containsString:@"Keyboard"] || [cn containsString:@"TextEffects"]) {
            [w setNeedsLayout];
            hgHideGlobeInRoot(w, hgEnabled);
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
    NSLog(@"[HideGlobe] loaded (fixed 1.0.4), hide globe = %@", hgEnabled ? @"ON" : @"OFF");
}
