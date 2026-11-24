#!/usr/bin/env swift
// 常亮 · macOS 13 及以上。可直接打开配套的 .app，也可用 swift KeepAwake.swift 运行。
import AppKit
import CoreGraphics
import IOKit.pwr_mgt
import SwiftUI

enum Cursor {
    // 始终使用 Quartz 全局坐标，兼容位于主屏左侧或上方的显示器。
    static func nearbyPoint(from origin: CGPoint, in bounds: CGRect) -> CGPoint? {
        let step = CGFloat(Int.random(in: 2...5))
        let candidates = [
            CGPoint(x: origin.x + step, y: origin.y),
            CGPoint(x: origin.x - step, y: origin.y),
            CGPoint(x: origin.x, y: origin.y + step),
            CGPoint(x: origin.x, y: origin.y - step)
        ]
        return candidates.filter { point in
            let nearSide = point.x < bounds.minX + 2 || point.x >= bounds.maxX - 2
            let nearEnd = point.y < bounds.minY + 2 || point.y >= bounds.maxY - 2
            return bounds.contains(point) && !(nearSide && nearEnd)
        }.randomElement()
    }

    @MainActor
    static func activityEvent(move: Bool) -> CGEvent? {
        // 只读取空闲时长和按钮状态。鼠标按住或最近 3 秒有操作时跳过。
        let anyInput = CGEventType(rawValue: UInt32.max)!
        guard NSEvent.pressedMouseButtons == 0,
              CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) >= 3,
              let origin = CGEvent(source: nil)?.location,
              let source = CGEventSource(stateID: .privateState) else { return nil }

        var target = origin
        if move {
            var display = CGDirectDisplayID()
            var count: UInt32 = 0
            guard CGGetDisplaysWithPoint(origin, 1, &display, &count) == .success, count > 0,
                  let nearby = nearbyPoint(from: origin, in: CGDisplayBounds(display)) else { return nil }
            target = nearby
        }

        // 防止合成事件短暂屏蔽紧接着发生的真实鼠标操作。
        source.localEventsSuppressionInterval = 0
        return CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                       mouseCursorPosition: target, mouseButton: .left)
    }
}

@MainActor
final class AwakeState: NSObject, ObservableObject {
    static let minuteRange = 1...30
    private static let intervalKey = "mouseIntervalMinutes"
    private static let secondsPerTick = 20

    @Published private(set) var enabled = false
    @Published private(set) var minutes: Int
    @Published private(set) var mayPostEvents = false
    @Published private(set) var errorMessage: String?
    @Published private var pauseReasons = Set<Notification.Name>()

    private let defaults: UserDefaults
    private var assertion: IOPMAssertionID = 0
    private var timer: Timer?
    private var ticksUntilMove = 0
    private let signals: [(center: NotificationCenter, pause: Notification.Name, resume: Notification.Name)]

    var paused: Bool { !pauseReasons.isEmpty }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.integer(forKey: Self.intervalKey)
        minutes = Self.minuteRange.contains(saved) ? saved : 5

        let workspace = NSWorkspace.shared.notificationCenter
        signals = [
            (workspace, NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification),
            (workspace, NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"),
             Notification.Name("com.apple.screenIsUnlocked"))
        ]
        super.init()
        for signal in signals {
            for name in [signal.pause, signal.resume] {
                if let distributed = signal.center as? DistributedNotificationCenter {
                    distributed.addObserver(self, selector: #selector(sessionChanged(_:)), name: name,
                                            object: nil, suspensionBehavior: .deliverImmediately)
                } else {
                    signal.center.addObserver(self, selector: #selector(sessionChanged(_:)), name: name, object: nil)
                }
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(applicationActivated(_:)),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationTerminating(_:)),
                                               name: NSApplication.willTerminateNotification, object: nil)
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        errorMessage = nil
        enabled = value
        reconcile()
    }

    func setMinutes(_ value: Int) {
        let newValue = min(max(value, Self.minuteRange.lowerBound), Self.minuteRange.upperBound)
        guard minutes != newValue else { return }
        minutes = newValue
        defaults.set(newValue, forKey: Self.intervalKey)
        if timer != nil { startTimer() }
    }

    func refreshPermission() {
        let granted = CGPreflightPostEventAccess()
        if granted != mayPostEvents { mayPostEvents = granted }
    }

    @objc private func applicationActivated(_ notification: Notification) { refreshPermission() }

    @objc private func applicationTerminating(_ notification: Notification) { stopWork() }

    func requestMouseAccess() {
        if !CGPreflightPostEventAccess() {
            _ = CGRequestPostEventAccess()
        }
        refreshPermission()
        if !mayPostEvents,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func sessionChanged(_ notification: Notification) {
        for signal in signals {
            if notification.name == signal.pause { pauseReasons.insert(signal.pause) }
            if notification.name == signal.resume { pauseReasons.remove(signal.pause) }
        }
        reconcile()
    }

    private func reconcile() {
        guard enabled && !paused else {
            stopWork()
            return
        }
        guard assertion == 0 else { return }
        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "常亮 · 保持屏幕唤醒" as CFString, &newID)
        guard result == kIOReturnSuccess else {
            enabled = false
            errorMessage = "系统暂未接受保持唤醒请求。请重新打开开关。"
            return
        }
        assertion = newID
        refreshPermission()
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        ticksUntilMove = minutes * 60 / Self.secondsPerTick
        let interval = TimeInterval(Self.secondsPerTick)
        let next = Timer(fireAt: Date(timeIntervalSinceNow: interval), interval: interval, target: self,
                         selector: #selector(tick(_:)), userInfo: nil, repeats: true)
        next.tolerance = 0.4
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    @objc private func tick(_ fired: Timer) {
        guard fired === timer else { return }
        ticksUntilMove -= 1
        let move = ticksUntilMove == 0
        if move { ticksUntilMove = minutes * 60 / Self.secondsPerTick }
        refreshPermission()
        // 屏保的空闲倒计时可能短于移动间隔。中间各次仅在指针原位报告活动。
        if mayPostEvents { Cursor.activityEvent(move: move)?.post(tap: .cghidEventTap) }
    }

    private func stopWork() {
        timer?.invalidate()
        timer = nil
        if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
    }
}

struct Controls: View {
    @ObservedObject var state: AwakeState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(get: { state.enabled }, set: state.setEnabled)) {
                Text("保持唤醒").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("鼠标移动间隔")
                    Spacer()
                    Text("\(state.minutes) 分钟").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { Double(state.minutes) }, set: { state.setMinutes(Int($0.rounded())) }),
                       in: Double(AwakeState.minuteRange.lowerBound)...Double(AwakeState.minuteRange.upperBound),
                       step: 1)
                    .accessibilityLabel("鼠标移动间隔")
                    .accessibilityValue("\(state.minutes) 分钟")
                HStack {
                    Text("1 分钟")
                    Spacer()
                    Text("30 分钟")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let message = state.errorMessage {
                Text(message).foregroundStyle(.red).font(.callout)
            } else if state.enabled && !state.mayPostEvents {
                VStack(alignment: .leading, spacing: 6) {
                    Text("已保持屏幕常亮。允许辅助功能后，即可定时移动鼠标。")
                        .font(.callout)
                    Button("允许移动鼠标…", action: state.requestMouseAccess)
                        .controlSize(.small)
                }
            }

            Divider()
            HStack {
                Text(footer).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .controlSize(.small)
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 290)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { state.refreshPermission() }
    }

    private var footer: String {
        if !state.enabled { return "当前使用系统休眠设置" }
        if state.paused { return "已暂停，回到桌面后继续" }
        if !state.mayPostEvents { return "鼠标轻移等待授权" }
        return "打字或拖拽时会跳过轻移"
    }
}

struct KeepAwakeApp: App {
    @StateObject private var state = AwakeState()

    var body: some Scene {
        MenuBarExtra {
            Controls(state: state)
        } label: {
            Label("常亮", systemImage: state.enabled ? "cup.and.saucer.fill" : "cup.and.saucer")
        }
        .menuBarExtraStyle(.window)
    }
}

NSApplication.shared.setActivationPolicy(.accessory)
KeepAwakeApp.main()
