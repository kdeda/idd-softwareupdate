//
//  idd-softwareupdateTests.swift
//  IDDFolderScan
//
//  Created by Klajd Deda on 01/05/23.
//  Copyright (C) 1997-2026 id-design, inc. All rights reserved.
//

import Foundation
import Testing
import Log4swift
import IDDSwift
import ComposableArchitecture
@testable import IDDSoftwareUpdate

struct IDDSoftwareUpdateTests {
//    static var allTests = [
//        ("test_failedToFetchUpdate", test_failedToFetchUpdate),
//        ("test_uptoDate", test_uptoDate),
//        ("test_displayNewVersion", test_displayNewVersion),
//        ("test_displayNewVersionLive", test_displayNewVersionLive),
//        ("test_displayNewVersionLive", test_displayNewVersionLive)
//    ]
    static var testConfig: FileLogConfig? {
        @Dependency(\.context) var context
        switch context {
        case .live:
            let logRootURL = URL.home.appendingPathComponent("Library/Logs/IDDSoftwareUpdate")
            return try? .init(logRootURL: logRootURL, appPrefix: "IDDSoftwareUpdate", appSuffix: "", daysToKeep: 30)
        case .preview:
            return nil
        case .test:
            let logRootURL = URL.home.appendingPathComponent("Library/Logs/IDDSoftwareUpdate")
            return try? .init(logRootURL: logRootURL, appPrefix: "IDDSoftwareUpdate", appSuffix: "", daysToKeep: 30)
        }
    }

    init() {
        Log4swift.configureCompactSettings()
        Log4swift.configure(fileLogConfig: Self.testConfig)
    }

    /**
     Emulate failing to fetch update
     */
    @MainActor
    @Test()
    func testFailedToFetchUpdate() async throws {
        prepareDependencies {
            $0.softwareUpdateClient = .liveValue
            $0.softwareUpdateClient.websiteURL = { _ in
                return URL(string: "https://test.whatsizemac.com")!
            }
        }
        let state: SoftwareUpdate.State = {
            var state = SoftwareUpdate.State()

            state.settings = .defaultItem
            return state
        }()        
        let store = TestStore(initialState: state) {
            SoftwareUpdate()
        }

        store.exhaustivity = .off

        Log4swift[Self.self].info("Starting")
        await store.send(.checkForUpdates)
        try? await Task.sleep(nanoseconds: .nanoseconds(milliseconds: 1250))
        
        let expectedUpdate = UpdateInfo(
            buildNumber: 8240,
            datePublished: "2025-10-11 23:57:50 +0000".date(withFormat: "yyyy-MM-dd HH:mm:ss Z"),
            downloadByteCount: 19774639,
            downloadSHA256: "C72C312AC3DB237E-15D4594A7E-E2473B9470A9-6B0E81E76F57-302D9439E88898",
            downloadURL: URL(string: "https://test.whatsizemac.com")!.appendingPathComponent("software/whatsize8/whatsize_8.2.4.pkg"),
            releaseNotesURL: URL(string: "https://test.whatsizemac.com")!.appendingPathComponent("software/whatsize8/release/notes.html"),
            shortVersion: "8.2.4",
            signature: "5QB44zviZ8TdNr5xQTSORLl8gKXpgIZy39oQJp2RZnWYxegzLrVxrtA6gbI7PZ3NM13D1taGxv6jW0UMDlNqmQGnuPjnGIXnLpDheFsEYUSA49spoDiHuyW5O0Gj0zijtdjdJVoqbQhCqnHbpGLNC+2IARkl3IWGfJpvdMMPTSxadTYIZSV1DEgjXrJ/1oHIfcKBqKkX2w6JldnkmbaHG6Cg1jTA6ckwuLfH1/8FAu3mCxuDLcAu/iYfs8ii4ag1O0mXGWHyurtKFg1MFhr7/PYReDtK2BLQGk4ClGCaIfHvcWj9Jhn9QFaPIbGvqH+IeGAgKCLF/qZHv2jKoZfksS+AmMPjbF+2VUE4BmU2DgTSv8mp+oTixgsXclGdQgF2qXM5PNfWl46jmcWOJw+oPojJOIvumfyy8R6S7V5pVIN7LPO4i7scRyy/8jMNgVi3YR9BWXYx+CrpdFOYaPt2LIzUbvne+NaCm/U4Z/7lFAB1K8VpXcFM6hW4b8JIRkv3wfnMTyhoyDplpqzhfy7zehpsBfWNmYfjEq3Js2i5wBVTxlWYG/15HR0S97ipJfuPLF/2SXCup+/lAa9vyvfStKXU4Jw9CFdXOmCRbg=="
        )

        await store.receive(.checkForUpdatesDidEnd(expectedUpdate, isBackground: false)) { newState in
            newState.installStep = .uptoDate
        }
        Log4swift[Self.self].info("Completed")
    }

    /**
     Test fetching an update
     */
    @MainActor
    @Test()
    func testDownloadUpdate() async throws {
        prepareDependencies {
            $0.softwareUpdateClient = .liveValue
            $0.softwareUpdateClient.websiteURL = { _ in
                return URL(string: "https://test.whatsizemac.com")!
            }
        }
        let expectedUpdate = UpdateInfo(
            buildNumber: 8240,
            datePublished: "2025-10-11 23:57:50 +0000".date(withFormat: "yyyy-MM-dd HH:mm:ss Z"),
            downloadByteCount: 19774639,
            downloadSHA256: "C72C312AC3DB237E-15D4594A7E-E2473B9470A9-6B0E81E76F57-302D9439E88898",
            downloadURL: URL(string: "https://test.whatsizemac.com")!.appendingPathComponent("software/whatsize8/whatsize_8.2.4.pkg"),
            releaseNotesURL: URL(string: "https://test.whatsizemac.com")!.appendingPathComponent("software/whatsize8/release/notes.html"),
            shortVersion: "8.2.4",
            signature: "5QB44zviZ8TdNr5xQTSORLl8gKXpgIZy39oQJp2RZnWYxegzLrVxrtA6gbI7PZ3NM13D1taGxv6jW0UMDlNqmQGnuPjnGIXnLpDheFsEYUSA49spoDiHuyW5O0Gj0zijtdjdJVoqbQhCqnHbpGLNC+2IARkl3IWGfJpvdMMPTSxadTYIZSV1DEgjXrJ/1oHIfcKBqKkX2w6JldnkmbaHG6Cg1jTA6ckwuLfH1/8FAu3mCxuDLcAu/iYfs8ii4ag1O0mXGWHyurtKFg1MFhr7/PYReDtK2BLQGk4ClGCaIfHvcWj9Jhn9QFaPIbGvqH+IeGAgKCLF/qZHv2jKoZfksS+AmMPjbF+2VUE4BmU2DgTSv8mp+oTixgsXclGdQgF2qXM5PNfWl46jmcWOJw+oPojJOIvumfyy8R6S7V5pVIN7LPO4i7scRyy/8jMNgVi3YR9BWXYx+CrpdFOYaPt2LIzUbvne+NaCm/U4Z/7lFAB1K8VpXcFM6hW4b8JIRkv3wfnMTyhoyDplpqzhfy7zehpsBfWNmYfjEq3Js2i5wBVTxlWYG/15HR0S97ipJfuPLF/2SXCup+/lAa9vyvfStKXU4Jw9CFdXOmCRbg=="
        )

        @Dependency(\.softwareUpdateClient) var softwareUpdateClient
        for await byteCount in try softwareUpdateClient.downloadUpdate(update: expectedUpdate) {
            Log4swift[Self.self].info("downloaded: '\(byteCount.decimalFormatted) bytes'")
        }
        Log4swift[Self.self].info("Completed")
    }

    
    
    
    
//    /**
//     Emulate obtaining an update item that is older or equal to the version we have.
//     */
//    @MainActor
//    func test_uptoDate() async {
//        let expectedUpdate = UpdateInfo(
//            buildNumber: 8100,
//            datePublished: Date().date(shiftedByDays: -1),
//            downloadByteCount: 19582879,
//            downloadSHA256: "",
//            downloadURL: URL(string: "https://test.whatsizemac.com")!.appendingPathComponent("software/whatsize8/whatsize_8.1.0.pkg"),
//            releaseNotesURL: URL(string: "https://test.whatsizemac.com")!.appendingPathComponent("software/whatsize8/release/notes.html"),
//            shortVersion: "8.1.0",
//            signature: ""
//        )
//
//        let store = TestStore(initialState: state) {
//            SoftwareUpdate()
//        } withDependencies: {
//            $0.continuousClock = clock
//            $0.softwareUpdateClient.websiteURL = {
//                URL(string: "https://test.whatsizemac.com")!
//            }
//            $0.softwareUpdateClient.appBuildNumber = { _ in
//                8930
//            }
//            $0.softwareUpdateClient.appShortVersion = {
//                "8.1.3"
//            }
//            $0.softwareUpdateClient.checkForUpdates = {
//                expectedUpdate
//            }
//        }
//
//        store.exhaustivity = .off
//
//        Log4swift[Self.self].info("Starting")
//        await store.send(.checkForUpdates)
//        await clock.advance()
//        await store.receive(.checkForUpdatesDidEnd(expectedUpdate, isBackground: false)) { newState in
//            newState.installStep = .uptoDate
//        }
//        Log4swift[Self.self].info("Completed")
//    }
//
//    /**
//     Emulate obtaining an update item that is more recent to the version we have.
//     */
//    @MainActor
//    func test_displayNewVersion() async {
//        @Dependency(\.softwareUpdateClient) var software
//        let expectedUpdate = UpdateInfo(
//            buildNumber: 8130,
//            datePublished: Date().date(shiftedByDays: -1),
//            downloadByteCount: 19582879,
//            downloadSHA256: "",
//            downloadURL: URL(string: "https://test.whatsizemac.com")!.appendingPathComponent("software/whatsize8/whatsize_8.1.3.pkg"),
//            releaseNotesURL: URL(string: "https://test.whatsizemac.com")!.appendingPathComponent("software/whatsize8/release/notes.html"),
//            shortVersion: "8.1.3",
//            signature: "")
//
//        let store = TestStore(initialState: state) {
//            SoftwareUpdate()
//        } withDependencies: {
//            $0.continuousClock = clock
//            $0.softwareUpdateClient.websiteURL = {
//                URL(string: "https://test.whatsizemac.com")!
//            }
//            $0.softwareUpdateClient.appBuildNumber = { _ in
//                8120
//            }
//            $0.softwareUpdateClient.appShortVersion = {
//                "8.1.2"
//            }
//            $0.softwareUpdateClient.checkForUpdates = {
//                expectedUpdate
//            }
//        }
//
//        store.exhaustivity = .off
//
//        Log4swift[Self.self].info("Starting")
//        await store.send(.checkForUpdates)
//        await clock.advance(by: .seconds(2))
//        await store.receive(.checkForUpdatesDidEnd(expectedUpdate, isBackground: false)) { newState in
//            newState.installStep = .displayNewVersion
//        }
//        Log4swift[Self.self].info("Completed")
//    }
//
//    /**
//     This will fetch the latest update live and compare it with what we said we have locally
//     */
//    @MainActor
//    func test_displayNewVersionLive() async {
//        let store = TestStore(initialState: state) {
//            SoftwareUpdate()
//        } withDependencies: {
//            $0.continuousClock = clock
//            $0.softwareUpdateClient.websiteURL = {
//                URL(string: "https://test.whatsizemac.com")!
//            }
//            $0.softwareUpdateClient.appBuildNumber = { _ in
//                8120
//            }
//            $0.softwareUpdateClient.appShortVersion = {
//                "8.1.2"
//            }
//            $0.softwareUpdateClient.checkForUpdates = SoftwareUpdateClient.liveValue.checkForUpdates
//        }
//
//        store.exhaustivity = .off
//
//        Log4swift[Self.self].info("Starting")
//        await store.send(.checkForUpdates)
//        await clock.advance(by: .seconds(5))
//        await store.receive({ action in
//            if case let .checkForUpdatesDidEnd(update, isBackground) = action {
//                Log4swift[Self.self].info("update: '\(update)' isBackground: '\(isBackground)'")
//                return true
//            }
//            return false
//        }) { newState in
//            @Dependency(\.softwareUpdateClient) var softwareUpdateClient
//
//            /**
//             The new version of the update is in the newState.update.shortVersion
//             */
//            Log4swift[Self.self].info("    appShortVersion: '\(softwareUpdateClient.appShortVersion())'")
//            Log4swift[Self.self].info("update.shortVersion: '\(newState.update.shortVersion)'")
//
//            newState.installStep = .displayNewVersion
//        }
//        Log4swift[Self.self].info("Completed")
//    }
}
