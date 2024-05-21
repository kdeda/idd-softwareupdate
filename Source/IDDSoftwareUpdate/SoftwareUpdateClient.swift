//
//  SoftwareUpdateClient.swift
//  IDDSoftwareUpdate
//
//  Created by Klajd Deda on 4/17/24.
//  Copyright (C) 1997-2024 id-design, inc. All rights reserved.
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
public struct SoftwareUpdateClient {
    public var websiteURL: () -> URL
    public var appBuildNumber: () -> Int
    public var appShortVersion: () -> String
    public var checkForUpdates: @Sendable () async -> UpdateInfo?
    public var downloadUpdate: @Sendable (_ update: UpdateInfo) throws -> AsyncStream<Int>
    public var installUpgrade: @Sendable (_ pkgFilePath: String) async -> Void

    public init(
        websiteURL: @escaping () -> URL,
        appBuildNumber: @escaping () -> Int,
        appShortVersion: @escaping () -> String,
        checkForUpdates: @escaping @Sendable () async -> UpdateInfo?,
        downloadUpdate: @escaping @Sendable (_: UpdateInfo) throws -> AsyncStream<Int>,
        installUpgrade: @escaping @Sendable (_: String) async -> Void
    ) {
        self.websiteURL = websiteURL
        self.appBuildNumber = appBuildNumber
        self.appShortVersion = appShortVersion
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
        @Dependency(\.continuousClock) var clock

        return Self(
            websiteURL: {
                guard let hostURLString = UserDefaults.standard.string(forKey: "AppDefaults.websiteURL"),
                      let hostURL = URL(string: hostURLString)
                else { return URL(string: "https://test.whatsizemac.com")! }

                return hostURL
            },
            appBuildNumber: {
#if DEBUG
                let buildNumber = Bundle.main.appVersion.buildNumber - 1 // will always find a new version
#else
                let buildNumber = Bundle.main.appVersion.buildNumber
#endif
                return buildNumber
            },
            appShortVersion: {
                Bundle.main.appVersion.shortVersion
            },
            checkForUpdates: {
                // DEDA DEBUG
                try? await clock.sleep(for: .milliseconds(500))

                let updateURL = UpdateInfo.hostURL.appendingPathComponent("software/whatsize8/release/update.json")
                var request = URLRequest(url: updateURL)

                request.cachePolicy = .reloadIgnoringCacheData
                guard let result = try? await URLSession.shared.data(for: request),
                      let response = result.1 as? HTTPURLResponse
                else {
                    Log4swift[Self.self].error("response: 'no response'")
                    return .none
                }

                guard response.statusCode == 200
                else {
                    Log4swift[Self.self].error("response: '\(response)'")
                    return .none
                }

                let data = result.0
                do {
                    let rv = try UpdateInfo.jsonDecoder.decode(UpdateInfo.self, from: data)

                    return rv.wasTempered ? .empty : rv.updatingHostURL
                } catch let error {
                    let json = String.init(data: data, encoding: .utf8) ?? ""
                    Log4swift[Self.self].error("json: '\(json)'")
                    Log4swift[Self.self].error("error: '\(error)'")
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
                                Log4swift[Self.self].error(".downloadUpdate: failed to open '\(update.downloadPKGURL.path)'")
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
        @Dependency(\.continuousClock) var clock

        return Self(
            websiteURL: {
                guard let hostURLString = UserDefaults.standard.string(forKey: "AppDefaults.websiteURL"),
                      let hostURL = URL(string: hostURLString)
                else { return URL(string: "https://test.whatsizemac.com")! }

                return hostURL
            },
            appBuildNumber: {
                return 8090
            },
            appShortVersion: {
                "8.0.9"
            },
            checkForUpdates: {
                return .none
            },
            downloadUpdate: { update in
                AsyncStream { continuation in
                    Log4swift[Self.self].info(function: "downloadUpdate", "update: '\(update)'")

                    let task = Task.detached {
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
        websiteURL: XCTUnimplemented("\(Self.self).websiteURL"),
        appBuildNumber: XCTUnimplemented("\(Self.self).appBuildNumber"),
        appShortVersion: XCTUnimplemented("\(Self.self).appShortVersion"),
        checkForUpdates: XCTUnimplemented("\(Self.self).checkForUpdates"),
        downloadUpdate: XCTUnimplemented("\(Self.self).downloadUpdate"),
        installUpgrade: XCTUnimplemented("\(Self.self).installUpgrade")
    )
}
