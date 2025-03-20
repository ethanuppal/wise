// Copyright (C) 2024 Ethan Uppal.
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 3 of the License only.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program.  If not, see <https://www.gnu.org/licenses/>.

@preconcurrency import ApplicationServices
import Cocoa

func error(_ items: Any..., fatal: Bool = true) {
    print("❌ ", terminator: "")
    for item in items {
        print(item, terminator: " ")
    }
    print()
    if fatal {
        exit(1)
    }
}

func hasAccessibilityPermissions() -> Bool {
    let options =
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

let left: CGFloat = 8
let right: CGFloat = 8
let top: CGFloat = 6
let bottom: CGFloat = 8
let appFrame = {
    var screenFrame = screenFrameExcludingNotch()
    screenFrame.origin.x += left
    screenFrame.origin.y += top
    screenFrame.size.width -= left + right
    screenFrame.size.height -= bottom + top
    return screenFrame
}()

/// so that the observers don't get `CFRelease`d
var observers: [pid_t: AXObserver] = [:]

let observerCallback: AXObserverCallback = {
    _, element, _, _ in
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)

    guard let app = NSRunningApplication(processIdentifier: pid),
        let bundleID = app.bundleIdentifier
    else {
        error("No app was found with PID \(pid)")
        return
    }

    switch setFrame(of: element, to: appFrame, bundleID: bundleID) {
    case .err(let message):
        error(message, fatal: false)
    default:
        break
    }

    print("✅ App \(bundleID) was resized")
}

@MainActor func observeWindows(
    of app: NSRunningApplication, withBundleId bundleID: String
) -> Result<(), String> {
    print("📄 Attempting to observe \(app)")

    let pid = app.processIdentifier
    let accessibilityElement = AXUIElementCreateApplication(pid)

    var observer: AXObserver?
    guard
        AXObserverCreate(pid, observerCallback, &observer)
            == .success, let observer
    else {
        return .err("Failed to create observer for \(bundleID) (PID: \(pid))")
    }

    observers[pid] = observer

    var appWindows: AnyObject?
    guard
        AXUIElementCopyAttributeValue(
            accessibilityElement, kAXWindowsAttribute as CFString, &appWindows)
            == .success, let appWindows = appWindows as? [AXUIElement]
    else {
        return .err("No windows found for \(bundleID)")
    }

    for window in appWindows {
        if AXObserverAddNotification(
            observer, window, kAXResizedNotification as CFString, nil)
            != .success
        {
            return .err(
                "Failed to add resize notification for window in \(bundleID)")
        } else {
            print("✅ Listening for resize events on window in \(bundleID)")
        }
    }

    let runLoopSource = AXObserverGetRunLoopSource(observer)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)

    return .ok(())
}

if !hasAccessibilityPermissions() {
    error("Please grant accessibility permissions")
}

let appsToObserve = CommandLine.arguments.dropFirst().map { bundleID in
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map
    {
        ($0, bundleID)
    }
}.flatMap { $0 }

for (app, bundleID) in appsToObserve {
    switch observeWindows(of: app, withBundleId: bundleID) {
    case .err(let message):
        error(message)
    default:
        break
    }
}

CFRunLoopRun()
