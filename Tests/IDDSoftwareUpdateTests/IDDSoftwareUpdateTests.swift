//
//  IDDSoftwareUpdateTests.swift
//  IDDFolderScan
//
//  Created by Klajd Deda on 01/05/23.
//  Copyright (C) 1997-2024 id-design, inc. All rights reserved.
//

import ComposableArchitecture
import Log4swift
import Logging
import IDDSwift
import XCTest

@testable import IDDSoftwareUpdate

final class IDDSoftwareUpdateTests: XCTestCase {
    let clock = TestClock()
    let state: SoftwareUpdate.State = {
        var state = SoftwareUpdate.State()

        state.settings = .defaultItem
        return state
    }()

    override static  func setUp() {
        super.setUp()

        // add -standardLog true to the arguments for the target, IDDSoftwareUpdateTests
        //
        Log4swift.configure(appName: "IDDSoftwareUpdateTests")
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
        await store.receive(\.delegate.failedToFetchUpdate)
        Log4swift[Self.self].info("Completed")
    }

    /**
     Emulate obtaining an update item that is older or equal to the version we have.
     */
    @MainActor
    func test_uptoDate() async {
        let store = TestStore(initialState: state) {
            SoftwareUpdate()
        } withDependencies: {
            $0.continuousClock = clock
            $0.softwareUpdateClient.websiteURL = {
                URL(string: "https://test.whatsizemac.com")!
            }
            $0.softwareUpdateClient.appBuildNumber = {
                8100
            }
            $0.softwareUpdateClient.appShortVersion = {
                "8.1.0"
            }
            $0.softwareUpdateClient.checkForUpdates = {
                UpdateInfo.empty
            }
        }

        store.exhaustivity = .off

        Log4swift[Self.self].info("Starting")
        await store.send(.checkForUpdates)
        await clock.advance()
        await store.receive(\.checkForUpdatesDidEnd) { newState in
            newState.installStep = .uptoDate
        }
        Log4swift[Self.self].info("Completed")
    }

    /**
     Emulate obtaining an update item that is more recent to the version we have.
     */
    @MainActor
    func test_displayNewVersion() async {
        let store = TestStore(initialState: state) {
            SoftwareUpdate()
        } withDependencies: {
            $0.continuousClock = clock
            $0.softwareUpdateClient.websiteURL = {
                URL(string: "https://test.whatsizemac.com")!
            }
            $0.softwareUpdateClient.appBuildNumber = {
                8090
            }
            $0.softwareUpdateClient.appShortVersion = {
                "8.0.9"
            }
            $0.softwareUpdateClient.checkForUpdates = {
                let rv = UpdateInfo(
                    buildNumber: 8100,
                    datePublished: Date().date(shiftedByDays: -1),
                    downloadByteCount: 19582879,
                    downloadSHA256: "",
                    downloadURL: URL(string: "https://test.whatsizemac.com")!.appendingPathComponent("software/whatsize8/whatsize_8.1.0.pkg"),
                    releaseNotesURL: URL(string: "https://test.whatsizemac.com")!.appendingPathComponent("software/whatsize8/release/notes.html"),
                    shortVersion: "8.1.0",
                    signature: "")
                return rv
            }
        }

        store.exhaustivity = .off

        Log4swift[Self.self].info("Starting")
        await store.send(.checkForUpdates)
        await clock.advance()
        await store.receive(\.checkForUpdatesDidEnd) { newState in
            newState.installStep = .displayNewVersion
        }
        Log4swift[Self.self].info("Completed")
    }

}
