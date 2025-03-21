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
var windowResizeObservers: [pid_t: (AXObserver, Set<UnsafeMutableRawPointer>)] =
    [:]
var windowCreatedOrDeletedObservers: [pid_t: AXObserver] = [:]

let windowResizeObserverCallback: AXObserverCallback = {
    _, element, _, _ in
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)

    guard let app = NSRunningApplication(processIdentifier: pid),
        let bundleID = app.bundleIdentifier
    else {
        error("No app was found with PID \(pid)", fatal: false)
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

let windowCreatedOrDeletedObserverCallback: AXObserverCallback = {
    _, element, notification, _ in
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)

    let windowAddress = Unmanaged.passUnretained(element).toOpaque()

    if windowResizeObservers[pid]?.1.contains(windowAddress) ?? false {
        print("📄 Ignoring already-seen window at \(windowAddress)")
        return
    }

    windowResizeObservers[pid]?.1.insert(windowAddress)

    guard let observer = windowResizeObservers[pid]?.0 else {
        return
    }

    guard let app = NSRunningApplication(processIdentifier: pid),
        let bundleID = app.bundleIdentifier
    else {
        error("No app was found with PID \(pid)", fatal: false)
        return
    }

    if notification == kAXWindowCreatedNotification as CFString {
        switch observeWindowResizing(
            element, observer: observer, bundleID: bundleID)
        {
        case .err(let message):
            error(message, fatal: false)
        default:
            break
        }
        print("✅ New window being tracked in \(bundleID)")
    } else {
        if windowResizeObservers[pid]?.1.contains(windowAddress) ?? false {
            let removeStatus = AXObserverRemoveNotification(
                observer, element, kAXResizedNotification as CFString)
            if removeStatus != .success {
                error(
                    "Failed to remove notification for window at \(windowAddress): \(removeStatus)",
                    fatal: false
                )
            } else {
                print("🛑 Stopped observing deleted window in \(bundleID)")
            }

            windowResizeObservers[pid]?.1.remove(windowAddress)
        } else {
            print("📄 Window at \(windowAddress) was not tracked")
        }
    }
}

@MainActor func observeWindowResizing(
    _ window: AXUIElement, observer: AXObserver, bundleID: String
)
    -> Result<(), String>
{
    switch setFrame(
        of: window, to: appFrame, bundleID: bundleID)
    {
    case .err(let message):
        return .err(message)
    default:
        break
    }

    if AXObserverAddNotification(
        observer, window, kAXResizedNotification as CFString, nil)
        != .success
    {
        return .err(
            "Failed to add resize notification for window in \(bundleID)")
    } else {
        print("✅ Listening for resize events on window in \(bundleID)")
    }

    return .ok(())
}

@MainActor func observeWindows(
    of app: NSRunningApplication, withBundleID bundleID: String
) -> Result<(), String> {
    print("📄 Attempting to observe \(app)")

    let pid = app.processIdentifier
    let accessibilityElement = AXUIElementCreateApplication(pid)

    var windowResizeObserver: AXObserver?
    guard
        AXObserverCreate(
            pid, windowResizeObserverCallback, &windowResizeObserver)
            == .success, let windowResizeObserver
    else {
        return .err("Failed to create observer for \(bundleID) (PID: \(pid))")
    }

    windowResizeObservers[pid] = (windowResizeObserver, Set())

    // we also want to observe if new windows are created
    var windowCreatedOrDeletedObserver: AXObserver?
    guard
        AXObserverCreate(
            pid, windowCreatedOrDeletedObserverCallback,
            &windowCreatedOrDeletedObserver)
            == .success, let windowCreatedOrDeletedObserver
    else {
        return .err(
            "Failed to create new-window-observer for \(bundleID) (PID: \(pid))"
        )
    }

    windowCreatedOrDeletedObservers[pid] = windowCreatedOrDeletedObserver

    if AXObserverAddNotification(
        windowCreatedOrDeletedObserver, accessibilityElement,
        kAXWindowCreatedNotification as CFString, nil)
        != .success
    {
        return .err(
            "Failed to add window-created notification for \(bundleID)"
        )
    } else {
        print(
            "✅ Listening for window-created events from \(bundleID)"
        )
    }
    if AXObserverAddNotification(
        windowCreatedOrDeletedObserver, accessibilityElement,
        kAXUIElementDestroyedNotification as CFString, nil)
        != .success
    {
        return .err(
            "Failed to add window-destroyed notification for \(bundleID)"
        )
    } else {
        print(
            "✅ Listening for window-destroyed events from \(bundleID)"
        )
    }

    var appWindows: AnyObject?
    guard
        AXUIElementCopyAttributeValue(
            accessibilityElement, kAXWindowsAttribute as CFString, &appWindows)
            == .success, let appWindows = appWindows as? [AXUIElement]
    else {
        return .err("No windows found for \(bundleID)")
    }

    for window in appWindows {
        switch observeWindowResizing(
            window, observer: windowResizeObserver, bundleID: bundleID)
        {
        case .err(let message):
            return .err(message)
        default:
            break
        }
    }

    let runLoopSource = AXObserverGetRunLoopSource(windowResizeObserver)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)

    let runLoopSource2 = AXObserverGetRunLoopSource(
        windowCreatedOrDeletedObserver)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource2, .defaultMode)

    return .ok(())
}

@MainActor func removeObserver(for app: NSRunningApplication) {
    let pid = app.processIdentifier
    if let windowResizeObserver = windowResizeObservers[pid]?.0,
        let windowCreatedOrDeletedObserver = windowCreatedOrDeletedObservers[
            pid]
    {

        let runLoopSource = AXObserverGetRunLoopSource(windowResizeObserver)
        CFRunLoopRemoveSource(
            CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        let runLoopSource2 = AXObserverGetRunLoopSource(
            windowCreatedOrDeletedObserver)
        CFRunLoopRemoveSource(
            CFRunLoopGetCurrent(), runLoopSource2, .defaultMode)

        windowResizeObservers.removeValue(forKey: pid)
        windowCreatedOrDeletedObservers.removeValue(forKey: pid)

        print(
            "✅ Removed observer for \(app.bundleIdentifier ?? "") (PID: \(pid))"
        )
    }
}

func registerAppNotifications(bundleIDsToObserve: Set<String>) {
    let notificationCenter = NSWorkspace.shared.notificationCenter

    notificationCenter.addObserver(
        forName: NSWorkspace.didLaunchApplicationNotification,
        object: nil,
        queue: .main
    ) { notification in
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
            let bundleID = app.bundleIdentifier,
            bundleIDsToObserve.contains(bundleID)
        else {
            return
        }

        print("📄 \(bundleID) launched")

        DispatchQueue.main.async {
            switch observeWindows(of: app, withBundleID: bundleID) {
            case .err(let message):
                error(message)
            default:
                break
            }
        }
    }

    notificationCenter.addObserver(
        forName: NSWorkspace.didTerminateApplicationNotification,
        object: nil,
        queue: .main
    ) { notification in
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
            let bundleID = app.bundleIdentifier,
            bundleIDsToObserve.contains(bundleID)
        else {
            return
        }

        print("📄 \(bundleID) closed")

        DispatchQueue.main.async {
            removeObserver(for: app)
        }
    }
}

if !hasAccessibilityPermissions() {
    error("Please grant accessibility permissions")
}

let bundleIDsToObserve = Set(CommandLine.arguments.dropFirst())

registerAppNotifications(bundleIDsToObserve: bundleIDsToObserve)

let appsToObserve = bundleIDsToObserve.map { bundleID in
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map
    {
        ($0, bundleID)
    }
}.flatMap { $0 }

for (app, bundleID) in appsToObserve {
    switch observeWindows(of: app, withBundleID: bundleID) {
    case .err(let message):
        error(message)
    default:
        break
    }
}

CFRunLoopRun()
