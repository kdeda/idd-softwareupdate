//
//  SoftwareUpdate.swift
//  idd-softwareupdate
//
//  Created by Klajd Deda on 4/3/24.
//  Copyright (C) 1997-2024 id-design, inc. All rights reserved.
//

import Foundation
import AppKit
import ComposableArchitecture
import IDDSwift
import Log4swift
import IDDAlert

/**
 Fast full test
 Build version 8.0.8

 sudo rm -rf /Applications/WhatSize.app
 open -a xcode /Users/kdeda/Developer/git.id-design.com/installer\_tools/xchelper/xchelper/WhatSize8/Project.json
 /Users/kdeda/Developer/git.id-design.com/installer\_tools/scripts/whatsize8.sh
 sudo installer -verbose -pkg ~/Desktop/Packages/WhatSize\_7.7.7/WhatSize.pkg -target /
 sudo installer -verbose -pkg ~/Desktop/Packages/WhatSize\_8.0.8/WhatSize.pkg -target /
 sudo installer -verbose -pkg ~/Desktop/Packages/WhatSize\_8.0.9/WhatSize.pkg -target /

 Build verion 8.0.9
 open -a xcode /Users/kdeda/Developer/git.id-design.com/installer\_tools/xchelper/xchelper/WhatSize8/Project.json
 /Users/kdeda/Developer/git.id-design.com/installer\_tools/scripts/whatsize8.sh
 
 Push it to local.whatsizemac.com
 
 Run version 8.0.8 in command line with arguments
 /Applications/WhatSize.app/Contents/MacOS/WhatSize -standardLog true -WhatSize.softwareUpdateHost http://local.whatsizemac.com
 */
@Reducer
public struct SoftwareUpdate: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var update: UpdateInfo = .empty
        public var downloadedByteCount = 0
        public var installStep: InstallStep = .none
        public var settings: Settings = Settings.lastSaved
        var useTestServer = false
        var optionPressed = false

        @Presents var alert: DNSAlert<Action.Alert>.State?

        public init() {
        }
    }

    public enum Action: Equatable, Sendable {
        case appDidStart
        case checkForUpdatesInBackgroundOnce
        case checkForUpdates
        case cancelCheckForUpdates
        case checkForUpdatesDidEnd(UpdateInfo, isBackground: Bool)

        case skipThisVersion
        case remindMeLater

        case downloadUpdate
        case cancelDownloadUpdate
        case downloading(Int)
        case downloadUpdateDidEnd

        case installAndRelaunch
        case installUpgradeCompleted(String)
        case installUpgradeDismiss

        case showSettings
        case setAutomatically(Bool)
        case setUpdateInterval(UpdateInterval)
        case dismissSettings

        // delegate
        case delegate(Delegate)
        public enum Delegate: Equatable, Sendable {
            case started
            case failedToFetchUpdate
            case cancelled
            case completed
        }

        case alert(PresentationAction<DNSAlert<Alert>.Action>)
        public enum Alert: Equatable, Sendable {
            case installAndRelaunch
        }
    }
    
    fileprivate enum CancelID: Hashable {
        case checkForUpdatesInBackgroundOnce
        case checkingForUpdates
        case downloadUpdate
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.softwareUpdateClient) var softwareUpdateClient

    public init() {
    }

    /**
     If this succeeds we will get restarted with -installUpgradeCompleted path\_to\_update

     Fast debug
     /Users/kdeda/Developer/build/Debug/WhatSize.app/Contents/MacOS/WhatSize -standardLog true -UpdateInfo.checkForUpdatesAutomatically true -UpdateInfo.installUpdateDebug true
     /Applications/WhatSize.app/Contents/MacOS/WhatSize -standardLog true -installUpgradeCompleted /Users/kdeda/Desktop/Packages/WhatSize_8.1.0/com.id-design.v8.whatsizehelper
     */
    fileprivate func installAndRelaunch(_ state: State) -> Effect<Action> {
        /// A path to a temporary folder that should contain your WhatSize.pkg and the UpdateInfo.json we are applying
        let pkgFilePath = state.update.downloadPKGURL.path

        return .run { send in
            await send(.delegate(.completed))
            // hang on a tinny bit
            try await clock.sleep(for: .milliseconds(50))
            await NSApplication.shared.hide(nil)

            let pkgFilePath = UpdateInfo.installUpdateDebug
            ? URL.home.appendingPathComponent("Desktop/Packages/WhatSize_8.1.0/WhatSize.pkg").path
            : pkgFilePath

            Log4swift[Self.self].info("filePath: '\(pkgFilePath)'")
            await softwareUpdateClient.installUpgrade(pkgFilePath)
        }
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appDidStart:
                // DEDA DEBUG
                // this is real code that gets called after the app is upgraded and relaunched
                if let downloadRootURL = UserDefaults.standard.string(forKey: "installUpgradeCompleted") {
                    return .send(.installUpgradeCompleted(downloadRootURL))
                }
                if UpdateInfo.checkForUpdatesAutomatically {
                    return .send(.checkForUpdates)
                }
                return .send(.checkForUpdatesInBackgroundOnce)

            case .checkForUpdatesInBackgroundOnce:
                // this should alwyas run and do nothing if we have ui up
                let isInteracting = state.installStep != .none
                let shouldCheck = state.settings.shouldCheckForUpdates
                let useTestServer = state.useTestServer
                let frequency = softwareUpdateClient.backgroundFrequency(state.optionPressed)

                Log4swift[Self.self].info(".checkForUpdatesInBackgroundOnce: frequency: '\(state.settings.updateInterval.name)' lastCheck: '\(state.settings.lastCheckString) 'nextCheck: '\(state.settings.nextCheckDate.stringWithDateFormatter(Settings.dateFormatter))' isInteracting: '\(isInteracting)' shouldCheck: '\(shouldCheck)'")
                return .run { send in
                    if !isInteracting && shouldCheck {
                        if let update = await softwareUpdateClient.checkForUpdates(useTestServer) {
                            await send(.checkForUpdatesDidEnd(update, isBackground: true))
                            return
                        }
                        // we will re-try in a bit
                        Log4swift[Self.self].error(".checkForUpdatesInBackgroundOnce handle failure to fetch: 'NOOP'")
                    }
                    try await clock.sleep(for: .seconds(frequency)) // sleep for a bit and retry
                    await send(.checkForUpdatesInBackgroundOnce)
                }
                .cancellable(id: CancelID.checkForUpdatesInBackgroundOnce, cancelInFlight: true)

            case .checkForUpdates:
                state.installStep = .checkForUpdates
                /**
                 When we option click do force upgrade this binary with new build from server
                 When we command, option click we will use the test.whatsizemac.com server
                 */
                let flags = MainActor.assumeIsolated {
                    NSApplication.shared.currentEvent?.modifierFlags ?? NSEvent.ModifierFlags(rawValue: 0)
                }
                state.useTestServer = flags.contains([.option, .command])
                if flags.contains([.option]) {
                    // option click, we will always trigger the need for upgrade
                    Log4swift[Self.self].info(".checkForUpdates option click path ... useTestServer: '\(state.useTestServer)'")
                    state.optionPressed = true
                }

                if UpdateInfo.installUpdateDebug {
                    // quick debuging
                    state.installStep = .installAndRelaunch

                    return .run { send in
                        Task.cancel(id: CancelID.checkForUpdatesInBackgroundOnce)
                        await send(.delegate(.started))
                        try await clock.sleep(for: .milliseconds(1250))
                        await send(.installAndRelaunch)
                    }
                }

                let useTestServer = state.useTestServer
                return .run { send in
                    Task.cancel(id: CancelID.checkForUpdatesInBackgroundOnce)
                    await send(.delegate(.started))
                    if let update = await softwareUpdateClient.checkForUpdates(useTestServer) {
                        await send(.checkForUpdatesDidEnd(update, isBackground: false))
                        return
                    }
                    try await clock.sleep(for: .milliseconds(250))
                    await send(.delegate(.failedToFetchUpdate))
                }
                .cancellable(id: CancelID.checkingForUpdates, cancelInFlight: true)

            case .cancelCheckForUpdates:
                return .run { send in
                    await send(.delegate(.cancelled))
                    Task.cancel(id: CancelID.checkingForUpdates)
                }

            case let .checkForUpdatesDidEnd(update, isBackground):
                let buildNumber = softwareUpdateClient.appBuildNumber(state.optionPressed)
                let shortVersion = softwareUpdateClient.appShortVersion()

                Log4swift[Self.self].info(".checkForUpdatesDidEnd update: '\(update.buildNumber)','\(update.shortVersion)', app: '\(buildNumber)','\(shortVersion)', datePublished: '\(update.datePublished)', downloadByteCount: '\(update.downloadByteCount.decimalFormatted)', isBackground: '\(isBackground ? "yuup" : "noop")'")

                state.update = update
                state.settings.lastCheckDate = Date()
                Settings.lastSaved = state.settings

                // background updates
                // be quiet unless a new update is found
                if isBackground {
                    if update.buildNumber > buildNumber {
                        Log4swift[Self.self].info(".checkForUpdatesDidEnd isBackground: '\(isBackground)', found update: '\(update.buildNumber)', greater than: '\(buildNumber)'")
                        if state.settings.skipVersion >= update.buildNumber  {
                            Log4swift[Self.self].info(".checkForUpdatesDidEnd skipVersion: '\(state.settings.skipVersion)'")
                        } else {
                            state.installStep = .displayNewVersion // onto the next step
                            return .send(.delegate(.started)) // become visible
                        }
                    }

                    // schedule the new fetch
                    return .send(.checkForUpdatesInBackgroundOnce)
                }

                // user initiated
                if update.buildNumber > buildNumber {
                    state.installStep = .displayNewVersion // onto the next step
                    // we should already be visible
                    return .none
                }

                state.installStep = .uptoDate
                return .none

            case .skipThisVersion:
                // basically we keep a note to ignore this version
                Log4swift[Self.self].error(".skipThisVersion: '\(state.update.buildNumber)'")
                state.settings.skipVersion = state.update.buildNumber
                Settings.lastSaved = state.settings
                return .send(.delegate(.completed))

            case .remindMeLater:
                // try again in a week
                Log4swift[Self.self].error(".remindMeLater: 'next week dude'")
                state.settings.lastCheckDate = Date().date(shiftedByDays: 7)
                Settings.lastSaved = state.settings
                return .send(.delegate(.completed))

            case .downloadUpdate:
                let update = state.update

                Log4swift[Self.self].info(".downloadUpdate: '\(update.downloadURL.absoluteString)'")
                Log4swift[Self.self].info(".downloadUpdate creating: '\(update.downloadRootURL.path)'")
                state.installStep = .downloadUpdate
                state.downloadedByteCount = 0

                return .run { send in
                    do {
                        for await byteCount in try softwareUpdateClient.downloadUpdate(update) {
                            await send(.downloading(byteCount))
                        }
                        try await clock.sleep(for: .milliseconds(250)) // let it breathe a bit
                        if !update.downloadPKGURL.fileExist {
                            Log4swift[Self.self].error(".downloadUpdate: failed to create: '\(update.downloadPKGURL.path)'")
                            await send(.delegate(.completed))
                            return
                        }

                        // Did we get what we were supposed to ?
                        var freshUpdate = update

                        freshUpdate.downloadSHA256 = update.downloadPKGURL.sha256With68Chars
                        freshUpdate.downloadByteCount = Int(update.downloadPKGURL.logicalSize)
                        if !freshUpdate.validateSignatures(update) {
                            await send(.delegate(.completed))
                            return
                        }

                        // store the just handled update
                        // so later we know the last update we applied
                        let json = try? UpdateInfo.jsonEncoder.encode(update)
                        try? (json ?? Data()).write(to: update.jsonFileURL)

                        // hand it of to the main thread
                        await send(.downloadUpdateDidEnd)
                    } catch {
                        Log4swift[Self.self].error(".downloadUpdate: error: '\(error)'")
                        await send(.delegate(.completed))
                    }
                }
                .cancellable(id: CancelID.downloadUpdate, cancelInFlight: true)

            case .cancelDownloadUpdate:
                return .run { send in
                    await send(.delegate(.cancelled))
                    Task.cancel(id: CancelID.downloadUpdate)
                }

            case let .downloading(newBytes):
                state.downloadedByteCount += newBytes
                Log4swift[Self.self].info(".downloading: '\(state.downloadedByteCount.decimalFormatted)'")
                return .none

            case .downloadUpdateDidEnd:
                Log4swift[Self.self].info(".downloadUpdateDidEnd: '\(state.update.downloadPKGURL.path)'")
                state.installStep = .installAndRelaunch
                return .none

            case .installAndRelaunch:
                state.alert = .init(
                    title: { TextState("This will install version \(state.update.shortVersion)") },
                    message: { TextState("The new version of WhatSize should restart in a second or two.") },
                    actions: {
                        ButtonState(action: .installAndRelaunch) {
                            TextState("OK")
                        }
                        ButtonState(role: .cancel) {
                            TextState("Cancel")
                        }
                    },
                    doNotShowAgainKey: "installAndRelaunch",
                    timeToLive: 6 * 30 * 24 * 60 * 60 // 6 months
                )

                guard state.alert == nil
                else { return .none }
                // just do it ...
                return installAndRelaunch(state)

            case let .installUpgradeCompleted(downloadRootPath):
                // fast debug
                // -installUpgradeCompleted /var/folders/_0/bb5dz9995mn2yv4bvcmhxwzr0000gn/T/whatsize_update_8090
                //
                Log4swift[Self.self].info(".installUpgradeCompleted: '\(downloadRootPath)'")

                let downloadRootURL = URL(fileURLWithPath: downloadRootPath)
                let jsonFileURL = downloadRootURL.appendingPathComponent("UpdateInfo.json")

                // store the just handled update
                let data = Data.init(withURL: jsonFileURL)
                let update = try? UpdateInfo.init(jsonData: data)

                state.update = update ?? .empty
                state.installStep = .installUpgradeCompleted
                return .send(.delegate(.started))

            case .installUpgradeDismiss:
                return .send(.delegate(.completed))

            case .showSettings:
                state.installStep = .settings
                return .none

            case let .setAutomatically(newValue):
                state.settings.automatically = newValue
                Settings.lastSaved = state.settings
                return .none

            case let .setUpdateInterval(newValue):
                state.settings.updateInterval = newValue
                Settings.lastSaved = state.settings
                return .none

            case .dismissSettings:
                return .send(.delegate(.completed))

            case .delegate:
                return .none

            case let .alert(.presented(.presented(subaction))):
                Log4swift[Self.self].info(".alert: \(subaction)")
                switch subaction {
                case .installAndRelaunch:
                    return installAndRelaunch(state)
                }

            case .alert:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert) { DNSAlert() }
    }
}
