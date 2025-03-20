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

func screenFrameExcludingNotch() -> CGRect {
    guard let mainScreen = NSScreen.main else {
        print("Main screen not available.")
        return .zero
    }

    let screenFrame = mainScreen.frame
    let visibleFrame = mainScreen.visibleFrame
    let notchHeight: CGFloat = 40  // screenFrame.height - visibleFrame.height
    print(screenFrame.height - visibleFrame.height)

    return CGRect(
        x: visibleFrame.origin.x,
        y: visibleFrame.origin.y + notchHeight,
        width: screenFrame.width,
        height: screenFrame.height - notchHeight
    )
}

func setFrame(of window: AXUIElement, to frame: CGRect, bundleID: String)
    -> Result<(), String>
{
    var canSetPosition: DarwinBoolean = false
    var canSetSize: DarwinBoolean = false

    let positionCheck = AXUIElementIsAttributeSettable(
        window, kAXPositionAttribute as CFString, &canSetPosition)
    let sizeCheck = AXUIElementIsAttributeSettable(
        window, kAXSizeAttribute as CFString, &canSetSize)

    if positionCheck != .success || !canSetPosition.boolValue {
        return .err("Cannot set position for \(bundleID): \(positionCheck).")
    }

    if sizeCheck != .success || !canSetSize.boolValue {
        return .err("Cannot set size for \(bundleID): \(sizeCheck).")
    }

    var position = frame.origin
    guard let positionValue = AXValueCreate(.cgPoint, &position) else {
        return .err("Failed to create position AXValue for \(bundleID).")
    }

    var size = frame.size
    guard let sizeValue = AXValueCreate(.cgSize, &size) else {
        return .err("Failed to create size AXValue for \(bundleID).")
    }

    let setPositionResult = AXUIElementSetAttributeValue(
        window, kAXPositionAttribute as CFString, positionValue)
    if setPositionResult != .success {
        return .err(
            "Failed to set position for \(bundleID): \(setPositionResult)")
    }

    let setSizeResult = AXUIElementSetAttributeValue(
        window, kAXSizeAttribute as CFString, sizeValue)
    if setSizeResult != .success {
        return .err("Failed to set size for \(bundleID): \(setSizeResult)")
    }

    print("\(bundleID) repositioned successfully.")

    return .ok(())
}
