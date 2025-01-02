//
//  idd-softwareupdateTests.swift
//  IDDFolderScan
//
//  Created by Klajd Deda on 01/05/23.
//  Copyright (C) 1997-2025 id-design, inc. All rights reserved.
//

import ComposableArchitecture
import Log4swift
import Logging
import IDDSwift
import XCTest

@testable import IDDSoftwareUpdate

final class IDDSoftwareUpdateTests: XCTestCase {
    static var allTests = [
        ("test_failedToFetchUpdate", test_failedToFetchUpdate),
        ("test_uptoDate", test_uptoDate),
        ("test_displayNewVersion", test_displayNewVersion),
        ("test_displayNewVersionLive", test_displayNewVersionLive),
        ("test_displayNewVersionLive", test_displayNewVersionLive)
    ]

    let clock = TestClock()
    let state: SoftwareUpdate.State = {
        var state = SoftwareUpdate.State()

        state.settings = .defaultItem
        return state
    }()

    static var logConfig = false

    override static func setUp() {
        guard !Self.logConfig
        else { return }

        LoggingSystem.bootstrap { label in
            ConsoleHandler(label: label)
        }
        Self.logConfig = true
        Log4swift[Self.self].info("\(String(repeating: "-", count: Bundle.main.appVersion.shortDescription.count))")
        Log4swift[Self.self].info("\(Bundle.main.appVersion.shortDescription)")
    }

    /**
     Emulate failing to fetch update
     */
    @MainActor
    func test_failedToFetchUpdate() async {
        let store = TestStore(initialState: state) {
            SoftwareUpdate()
        } withDependencies: {
            $0.continuousClock = clock
            $0.softwareUpdateClient.websiteURL = {
                URL(string: "https://test.whatsizemac.com")!
            }
            $0.softwareUpdateClient.checkForUpdates = {
                .none
            }
        }

        store.exhaustivity = .off

        Log4swift[Self.self].info("Starting")
        await store.send(.checkForUpdates)
        await clock.advance(by: .seconds(1)) // more than what we were sleeping over on the action side
        await store.receive(.delegate(.failedToFetchUpdate))
        Log4swift[Self.self].info("Completed")
    }

    /**
     Emulate obtaining an update item that is older or equal to the version we have.
     */
    @MainActor
    func test_uptoDate() async {
        let expectedUpdate = UpdateInfo(
            buildNumber: 8100,
            datePublished: Date().date(shiftedByDays: -1),
            downloadByteCount: 19582879,
            downloadSHA256: "",
            downloadURL: URL(string: "https://test.whatsizemac.com")!.appendingPathComponent("software/whatsize8/whatsize_8.1.0.pkg"),
            releaseNotesURL: URL(string: "https://test.whatsizemac.com")!.appendingPathComponent("software/whatsize8/release/notes.html"),
            shortVersion: "8.1.0",
            signature: ""
        )

        let store = TestStore(initialState: state) {
            SoftwareUpdate()
        } withDependencies: {
            $0.continuousClock = clock
            $0.softwareUpdateClient.websiteURL = {
                URL(string: "https://test.whatsizemac.com")!
            }
            $0.softwareUpdateClient.appBuildNumber = { _ in
                8930
            }
            $0.softwareUpdateClient.appShortVersion = {
                "8.1.3"
            }
            $0.softwareUpdateClient.checkForUpdates = {
                expectedUpdate
            }
        }

        store.exhaustivity = .off

        Log4swift[Self.self].info("Starting")
        await store.send(.checkForUpdates)
        await clock.advance()
        await store.receive(.checkForUpdatesDidEnd(expectedUpdate, isBackground: false)) { newState in
            newState.installStep = .uptoDate
        }
        Log4swift[Self.self].info("Completed")
    }

    /**
     Emulate obtaining an update item that is more recent to the version we have.
     */
    @MainActor
    func test_displayNewVersion() async {
        @Dependency(\.softwareUpdateClient) var software
        let expectedUpdate = UpdateInfo(
            buildNumber: 8130,
            datePublished: Date().date(shiftedByDays: -1),
            downloadByteCount: 19582879,
            downloadSHA256: "",
            downloadURL: URL(string: "https://test.whatsizemac.com")!.appendingPathComponent("software/whatsize8/whatsize_8.1.3.pkg"),
            releaseNotesURL: URL(string: "https://test.whatsizemac.com")!.appendingPathComponent("software/whatsize8/release/notes.html"),
            shortVersion: "8.1.3",
            signature: "")

        let store = TestStore(initialState: state) {
            SoftwareUpdate()
        } withDependencies: {
            $0.continuousClock = clock
            $0.softwareUpdateClient.websiteURL = {
                URL(string: "https://test.whatsizemac.com")!
            }
            $0.softwareUpdateClient.appBuildNumber = { _ in
                8120
            }
            $0.softwareUpdateClient.appShortVersion = {
                "8.1.2"
            }
            $0.softwareUpdateClient.checkForUpdates = {
                expectedUpdate
            }
        }

        store.exhaustivity = .off

        Log4swift[Self.self].info("Starting")
        await store.send(.checkForUpdates)
        await clock.advance(by: .seconds(2))
        await store.receive(.checkForUpdatesDidEnd(expectedUpdate, isBackground: false)) { newState in
            newState.installStep = .displayNewVersion
        }
        Log4swift[Self.self].info("Completed")
    }

    /**
     This will fetch the latest update live and compare it with what we said we have locally
     */
    @MainActor
    func test_displayNewVersionLive() async {
        let store = TestStore(initialState: state) {
            SoftwareUpdate()
        } withDependencies: {
            $0.continuousClock = clock
            $0.softwareUpdateClient.websiteURL = {
                URL(string: "https://test.whatsizemac.com")!
            }
            $0.softwareUpdateClient.appBuildNumber = { _ in
                8120
            }
            $0.softwareUpdateClient.appShortVersion = {
                "8.1.2"
            }
            $0.softwareUpdateClient.checkForUpdates = SoftwareUpdateClient.liveValue.checkForUpdates
        }

        store.exhaustivity = .off

        Log4swift[Self.self].info("Starting")
        await store.send(.checkForUpdates)
        await clock.advance(by: .seconds(5))
        await store.receive({ action in
            if case let .checkForUpdatesDidEnd(update, isBackground) = action {
                Log4swift[Self.self].info("update: '\(update)' isBackground: '\(isBackground)'")
                return true
            }
            return false
        }) { newState in
            @Dependency(\.softwareUpdateClient) var softwareUpdateClient

            /**
             The new version of the update is in the newState.update.shortVersion
             */
            Log4swift[Self.self].info("    appShortVersion: '\(softwareUpdateClient.appShortVersion())'")
            Log4swift[Self.self].info("update.shortVersion: '\(newState.update.shortVersion)'")

            newState.installStep = .displayNewVersion
        }
        Log4swift[Self.self].info("Completed")
    }
}
