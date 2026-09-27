// HGSettingsController — 隐藏地球图标的设置面板主控制器
// 偏好读写直落 jbroot plist（与 Tweak.xm 完全一致），并广播 darwin 通知让 tweak 实时刷新。

#import <Preferences/Preferences.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#define HG_SUITE @"com.yzdmm.hideglobe"
#define HG_DARWIN_NOTI "com.yzdmm.hideglobe.prefschanged"

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

static NSDictionary *HGPrefDict(void) {
    return [NSDictionary dictionaryWithContentsOfFile:hgPrefsPath()] ?: @{};
}

static void HGPostChanged(void) {
    @try {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFSTR(HG_DARWIN_NOTI), NULL, NULL, TRUE);
    } @catch (NSException *e) {}
}

static void HGWriteKey(NSString *key, id value) {
    @try {
        NSString *p = hgPrefsPath();
        NSMutableDictionary *d = [HGPrefDict() mutableCopy] ?: [NSMutableDictionary dictionary];
        if (value) d[key] = value; else [d removeObjectForKey:key];
        if ([d writeToFile:p atomically:YES]) { HGPostChanged(); return; }
        // 文件写失败退回 CFPreferences（面板进程 root，RootHide 下同样落 jbroot）
        CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                 (__bridge CFPropertyListRef)value,
                                 (__bridge CFStringRef)HG_SUITE);
        CFPreferencesSynchronize((__bridge CFStringRef)HG_SUITE,
                                 kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        HGPostChanged();
    } @catch (NSException *e) {}
}

@interface HGSettingsController : PSListController
@end

@implementation HGSettingsController

- (id)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

// PSSwitchCell 改值 → super 写入（RootHide 下落 jbroot）→ 再直写文件双保险 → 广播通知
- (void)setPreferenceValue:(id)value specifier:(id)specifier {
    @try {
        [super setPreferenceValue:value specifier:specifier];
        NSString *key = [specifier propertyForKey:@"key"];
        if ([key isKindOfClass:[NSString class]] && key.length) {
            NSString *p = hgPrefsPath();
            if (p) {
                NSMutableDictionary *d = [HGPrefDict() mutableCopy] ?: [NSMutableDictionary dictionary];
                if (value) d[key] = value;
                [d writeToFile:p atomically:YES];
            }
        }
        HGPostChanged();
    } @catch (NSException *e) {}
}

@end
