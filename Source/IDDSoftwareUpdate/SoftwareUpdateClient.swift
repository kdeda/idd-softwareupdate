//
//  SoftwareUpdateClient.swift
//  idd-softwareupdate
//
//  Created by Klajd Deda on 4/17/24.
//  Copyright (C) 1997-2025 id-design, inc. All rights reserved.
//

import Foundation
import IDDSwift
import Log4swift
import ComposableArchitecture
import XCTestDynamicOverlay

enum DownloadUpdateError: LocalizedError, Equatable {
    case error(String)
    case failedToOpen(URL)

    public var errorDescription: String {
        switch self {
        case let .error(errorString):  return errorString
        case let .failedToOpen(url):  return "Failed to open: '\(url.path)'"
        }
    }
}

/**
 Helpers to obtain the last update and fetch it if needed.
 */
public struct SoftwareUpdateClient: Sendable {
    /**
     Web site to hit, Override it !
     ```
    self.store = Store(
         initialState: AppReducer.State(),
         reducer: AppReducer.init,
         withDependencies: {
             $0.softwareUpdateClient.websiteURL = {
                 guard let hostURLString = UserDefaults.standard.string(forKey: "AppDefaults.websiteURL"),
                       let hostURL = URL(string: hostURLString)
                 else { return URL(string: "https://www.whatsizemac.com")! }
                 return hostURL
             }
         }
     )
     ```
     */
    public var websiteURL: @Sendable (_ useTestServer: Bool) -> URL

    // currently installed appNumber
    public var appBuildNumber: @Sendable (_ optionPressed: Bool) -> Int

    // currently installed short version
    public var appShortVersion: @Sendable () -> String

    // frequency in seconds to perform background updates, default is once an hour
    public var backgroundFrequency: @Sendable (_ optionPressed: Bool) -> Int

    // fetch the new update
    public var checkForUpdates: @Sendable (_ useTestServer: Bool) async -> UpdateInfo?

    // download the bytes for the new update
    public var downloadUpdate: @Sendable (_ update: UpdateInfo) throws -> AsyncStream<Int>

    // install the update previosly downloaded
    public var installUpgrade: @Sendable (_ pkgFilePath: String) async -> Void

    public init(
        websiteURL: @Sendable @escaping (_ useTestServer: Bool) -> URL,
        appBuildNumber: @Sendable @escaping (_ optionPressed: Bool) -> Int,
        appShortVersion: @Sendable @escaping () -> String,
        backgroundFrequency: @Sendable @escaping (_ optionPressed: Bool) -> Int,
        checkForUpdates: @Sendable @escaping (_ useTestServer: Bool) async -> UpdateInfo?,
        downloadUpdate: @Sendable @escaping (_ update: UpdateInfo) throws -> AsyncStream<Int>,
        installUpgrade: @Sendable @escaping (_ pkgFilePath: String) async -> Void
    ) {
        self.websiteURL = websiteURL
        self.appBuildNumber = appBuildNumber
        self.appShortVersion = appShortVersion
        self.backgroundFrequency = backgroundFrequency
        self.checkForUpdates = checkForUpdates
        self.downloadUpdate = downloadUpdate
        self.installUpgrade = installUpgrade
    }
}

extension DependencyValues {
    public var softwareUpdateClient: SoftwareUpdateClient {
        get { self[SoftwareUpdateClient.self] }
        set { self[SoftwareUpdateClient.self] = newValue }
    }
}

extension SoftwareUpdateClient: DependencyKey {
    public static let liveValue: Self = {
        let appBuildNumber_ = LockIsolated(Bundle.main.appVersion.buildNumber)

        return Self(
            websiteURL: { useTestServer in
                Log4swift[Self.self].error(function: "websiteURL", "override me ...")
                fatalError()
            },
            appBuildNumber: { optionPressed in
                var buildNumber = Bundle.main.appVersion.buildNumber

                if optionPressed {
                    buildNumber -= 1
                }
                return buildNumber
            },
            appShortVersion: {
                Bundle.main.appVersion.shortVersion
            },
            backgroundFrequency: { optionPressed in
                var frequency = 60 * 60 // in seconds
                
                if optionPressed {
                    frequency = 5
                }
                return frequency
            },
            checkForUpdates: { useTestServer in
                @Dependency(\.continuousClock) var clock
                // DEDA DEBUG
                try? await clock.sleep(for: .milliseconds(250))

                let updateURL = UpdateInfo.hostURL(useTestServer).appendingPathComponent("software/whatsize8/release/update.json")
                Log4swift[Self.self].info(function: "checkForUpdates", "UpdateInfo.hostURL: '\(updateURL.absoluteString)'")
                var request = URLRequest(url: updateURL)

                request.cachePolicy = .reloadIgnoringCacheData
                guard let result = try? await URLSession.shared.data(for: request),
                      let response = result.1 as? HTTPURLResponse
                else {
                    Log4swift[Self.self].error(function: "checkForUpdates", "response: 'no response'")
                    return .none
                }

                guard response.statusCode == 200
                else {
                    Log4swift[Self.self].error(function: "checkForUpdates", "response: '\(response)'")
                    return .none
                }

                let data = result.0
                do {
                    var rv = try UpdateInfo.init(jsonData: data)

                    rv.useTestServer = useTestServer
                    return rv.wasTempered ? .empty : rv.updatingHostURL
                } catch let error {
                    let json = String.init(data: data, encoding: .utf8) ?? ""
                    Log4swift[Self.self].error(function: "checkForUpdates", "json: '\(json)'")
                    Log4swift[Self.self].error(function: "checkForUpdates", "error: '\(error)'")
                }
                return .none
            },
            downloadUpdate: { update in
                AsyncStream { continuation in
                    let downloadURL = update.downloadURL

                    Log4swift[Self.self].info(function: "downloadUpdate", "update: '\(update)'")
                    let task = Task.detached {
                        do {
                            // make sure the temporary folder is empty
                            _ = FileManager.default.removeItemIfExist(at: update.downloadRootURL)
                            FileManager.default.createDirectoryIfMissing(at: update.downloadRootURL)

                            // create a fileHandle
                            try? Data().write(to: update.downloadPKGURL)
                            guard let fileHandle = try? FileHandle(forWritingTo: update.downloadPKGURL)
                            else {
                                Log4swift[Self.self].error(function: "downloadUpdate", "failed to open '\(update.downloadPKGURL.path)'")
                                // continuation.yield(.error(.failedToOpen(update.downloadPKGURL)))
                                throw DownloadUpdateError.failedToOpen(update.downloadPKGURL)
                            }

                            // download the binary and store it to the fileHandle
                            let (asyncBytes, _) = try await URLSession.shared.bytes(from: downloadURL)
                            var buffer = Data()
                            var threshold = Date()

                            for try await byte in asyncBytes {
                                buffer.append(byte)

                                if threshold.elapsedTimeInMilliseconds > 100 { // don't care but 10/second
                                    fileHandle.write(buffer)

                                    // notify main thread about download progress
                                    continuation.yield(buffer.count)
                                    buffer = Data()
                                    threshold = Date()
                                }
                            }

                            // write the last bits
                            fileHandle.write(buffer)
                            continuation.yield(buffer.count)
                        } catch {
                            throw DownloadUpdateError.error(error.localizedDescription)
                        }
                        continuation.finish()
                    }

                    continuation.onTermination = { _ in
                        Log4swift[Self.self].info(function: "downloadUpdate", "update: '\(update)'")
                        task.cancel()
                    }
                }
            },
            installUpgrade: { pkgFilePath in
                Log4swift[Self.self].error(function: "installUpgrade", "NOOP, please plguin the proper imp for this")
            }
        )
    }()

    public static let previewValue: Self = {
        return Self(
            websiteURL: { useTestServer in
                guard let hostURLString = UserDefaults.standard.string(forKey: "AppDefaults.websiteURL"),
                      let hostURL = URL(string: hostURLString)
                else { return URL(string: "https://test.whatsizemac.com")! }

                return hostURL
            },
            appBuildNumber: { _ in
                return 8090
            },
            appShortVersion: {
                "8.0.9"
            },
            backgroundFrequency: { _ in
                5
            },
            checkForUpdates: { useTestServer in
                return .none
            },
            downloadUpdate: { update in
                AsyncStream { continuation in
                    Log4swift[Self.self].info(function: "downloadUpdate", "update: '\(update)'")

                    let task = Task.detached {
                        @Dependency(\.continuousClock) var clock
                        
                        await (0 ..< 100).asyncForEach { _ in
                            try? await clock.sleep(for: .milliseconds(250))
                            continuation.yield(100)
                        }
                        continuation.finish()
                    }

                    continuation.onTermination = { _ in
                        Log4swift[Self.self].info(function: "downloadUpdate", "update: '\(update)'")
                        task.cancel()
                    }
                }
            },
            installUpgrade: { pkgFilePath in
                Log4swift[Self.self].error(function: "installUpgrade", "NOOP, please plguin the proper imp for this")
            }
        )
    }()
}

extension SoftwareUpdateClient: TestDependencyKey {
    public static let testValue = Self(
        websiteURL: unimplemented("\(Self.self).websiteURL", placeholder: .home),
        appBuildNumber: unimplemented("\(Self.self).appBuildNumber", placeholder: 1010),
        appShortVersion: unimplemented("\(Self.self).appShortVersion", placeholder: "1.0.1"),
        backgroundFrequency: unimplemented("\(Self.self).backgroundFrequency", placeholder: 10),
        checkForUpdates: unimplemented("\(Self.self).checkForUpdates", placeholder: .none),
        downloadUpdate: unimplemented("\(Self.self).downloadUpdate"),
        installUpgrade: unimplemented("\(Self.self).installUpgrade")
    )
}
