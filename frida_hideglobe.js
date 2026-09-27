// frida_hideglobe.js — 实锤地球键的 representedString 并实时隐藏/恢复
//
// 用法:
//   frida -U -n <App名或进程名> -l frida_hideglobe.js
//   frida -U -f com.tencent.xin -l frida_hideglobe.js --no-pause
//
// 步骤:
//   1) 先进任意能弹键盘的 App，弹出键盘
//   2) dumpKeys()      —— 打印所有键的 className + representedString，确认 globe 串
//   3) hideGlobe(true) —— 隐藏；hideGlobe(false) —— 恢复
//   脚本同时每 0.5s 自动隐藏一次，方便直接看效果
'use strict';

function findImpl() {
    try {
        const app = ObjC.classes.UIApplication.sharedApplication();
        const ws = app.windows();
        for (let i = 0; i < ws.count(); i++) {
            const r = walkImpl(ws.objectAtIndex(i));
            if (r) return r;
        }
    } catch (e) {}
    return null;
}
function walkImpl(v) {
    if (!v) return null;
    try {
        if ((v.$className || '').indexOf('UIKeyboardImpl') >= 0) return v;
        const subs = v.subviews();
        if (subs) for (let i = 0; i < subs.count(); i++) {
            const r = walkImpl(subs.objectAtIndex(i));
            if (r) return r;
        }
    } catch (e) {}
    return null;
}

function getLayout() {
    const kb = findImpl();
    if (!kb) return null;
    return kb.layout ? kb.layout() : null;
}

// 打印所有键的 representedString，确认 globe 识别串
function dumpKeys() {
    const layout = getLayout();
    if (!layout) { console.log('[HG] 没找到 UIKeyboardImpl / layout（先弹出键盘）'); return; }
    console.log('[HG] layout class:', layout.$className);
    let n = 0;
    (function walk(v) {
        if (!v) return;
        try {
            if (v.respondsToSelector_(ObjC.selector('representedString'))) {
                const rs = v.representedString();
                if (rs && rs.length) { console.log('  key:', v.$className, 'rep=', rs); n++; }
            }
            const subs = v.subviews();
            if (subs) for (let i = 0; i < subs.count(); i++) walk(subs.objectAtIndex(i));
        } catch (e) {}
    })(layout);
    console.log('[HG] 共', n, '个带 representedString 的键');
}

// 隐藏/恢复 globe 键（默认识别串 "globe"，大小写不敏感）
function hideGlobe(hide) {
    const layout = getLayout();
    if (!layout) { console.log('[HG] 没找到 layout'); return; }
    const target = 'globe';
    let hit = 0;
    (function walk(v) {
        if (!v) return;
        try {
            if (v.respondsToSelector_(ObjC.selector('representedString'))) {
                const rs = v.representedString();
                if (rs && rs.toLowerCase().indexOf(target) >= 0) {
                    v.setHidden_(hide);
                    v.setUserInteractionEnabled_(!hide);
                    hit++;
                }
            }
            const subs = v.subviews();
            if (subs) for (let i = 0; i < subs.count(); i++) walk(subs.objectAtIndex(i));
        } catch (e) {}
    })(layout);
    console.log('[HG]', hide ? '已隐藏' : '已恢复', hit, '个 globe 键视图');
}

global.dumpKeys = dumpKeys;
global.hideGlobe = hideGlobe;

console.log('[HG] 先弹键盘，再跑 dumpKeys() 看所有键的 representedString；确认后 hideGlobe(true)');

// 自动隐藏循环（实时验证）
const auto = setInterval(() => {
    const layout = getLayout();
    if (!layout) return;
    let hit = 0;
    (function walk(v) {
        if (!v) return;
        try {
            if (v.respondsToSelector_(ObjC.selector('representedString'))) {
                const rs = v.representedString();
                if (rs && rs.toLowerCase().indexOf('globe') >= 0) {
                    v.setHidden_(true); v.setUserInteractionEnabled_(false); hit++;
                }
            }
            const s = v.subviews();
            if (s) for (let i = 0; i < s.count(); i++) walk(s.objectAtIndex(i));
        } catch (e) {}
    })(layout);
    if (hit) console.log('[HG] auto-hid', hit);
}, 500);
