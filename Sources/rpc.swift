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

import Cocoa
import Network

@available(macOS 10.14, *)
func receiveJSON(on connection: NWConnection) {
    DispatchQueue.global().async {
        var connectionActive = true
        var buffer = Data()

        while connectionActive {
            let semaphore = DispatchSemaphore(value: 0)

            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096)
            { data, _, isComplete, error in
                if let data = data, !data.isEmpty {
                    buffer.append(data)

                    if let rawString = String(data: buffer, encoding: .utf8) {
                        if let range = rawString.range(of: "\r\n\r\n") {
                            let bodyStart = rawString[range.upperBound...]

                            if let bodyData = bodyStart.data(using: .utf8) {
                                do {
                                    if let jsonObject =
                                        try JSONSerialization.jsonObject(
                                            with: bodyData, options: [])
                                        as? [String: Any],
                                        let bundleID = jsonObject[
                                            "bundleID"]
                                            as? String?,
                                        let bundleID,
                                        let position = jsonObject[
                                            "position"]
                                            as? String?, let position
                                    {
                                        if let rect = appFrameLookup[
                                            position]
                                        {
                                            print(rect)
                                            DispatchQueue.main.async {
                                                appFrames[bundleID] = rect
                                                for app
                                                    in NSRunningApplication
                                                    .runningApplications(
                                                        withBundleIdentifier:
                                                            bundleID)
                                                {
                                                    let accessibilityElement =
                                                        AXUIElementCreateApplication(
                                                            app
                                                                .processIdentifier
                                                        )
                                                    switch getWindowsFromAppAccessibilityElement(
                                                        accessibilityElement:
                                                            accessibilityElement,
                                                        bundleID: bundleID)
                                                    {
                                                    case .ok(let windows):
                                                        for window
                                                            in windows
                                                        {
                                                            switch setFrame(
                                                                of:
                                                                    window,
                                                                bundleID:
                                                                    bundleID
                                                            ) {
                                                            case .err(
                                                                let message):
                                                                wise.error(
                                                                    message)
                                                            default: break
                                                            }
                                                        }
                                                    case .err(let message):
                                                        wise.error(message)
                                                    }
                                                }
                                            }

                                            // print("📥 Received JSON: \(jsonObject)")
                                        }
                                    }
                                } catch {
                                    wise.error(
                                        "Decoding JSON body: \(error)",
                                        fatal: false)
                                }
                            } else {
                                wise.error(
                                    "Failed to extract body data.",
                                    fatal: false
                                )
                            }

                            connection.cancel()
                            connectionActive = false
                        }
                    }
                }

                if isComplete {
                    print("🔚 Connection ended")
                    connection.cancel()
                    connectionActive = false
                } else if let error {
                    wise.error("Connection error: \(error)", fatal: false)
                    connection.cancel()
                    connectionActive = false
                }

                semaphore.signal()
            }

            semaphore.wait()
        }
    }
}

@available(macOS 10.14, *)
func startSocketListener() {
    let port: NWEndpoint.Port = 12345
    do {
        let listener = try NWListener(using: .tcp, on: port)
        listener.stateUpdateHandler = { newState in
            print("🔄 Listener state changed: \(newState)")
        }
        listener.newConnectionHandler = { connection in
            print("📡 New connection from: \(connection.endpoint)")
            connection.start(queue: .global())
            receiveJSON(on: connection)
        }
        listener.start(queue: .global())
        print("✅ Socket listener started on port \(port)")
    } catch {
        wise.error("Failed to start socket listener: \(error)")
    }
}
