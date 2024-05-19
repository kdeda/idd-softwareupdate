//
//  SoftwareUpdate.swift
//  IDDSoftwareUpdate
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

@Reducer
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
struct SoftwareUpdate {
    @ObservableState
    struct State: Equatable {
        var update: UpdateInfo = .empty
        var downloadedByteCount = 0
        var installStep: InstallStep = .none
        var settings: Settings = Settings.lastSaved

        @Presents var alert: DNSAlert<Action.Alert>.State?
    }

    enum Action: Equatable {
        case appDidStart
        case checkForUpdatesInBackgroundOnce
        case checkForUpdates
        case cancelCheckForUpdates
        case checkForUpdatesDidEnd(UpdateInfo, Bool)

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
        enum Delegate: Equatable {
            case started
            case failedToFetchUpdate
            case cancelled
            case completed
        }

        case alert(PresentationAction<DNSAlert<Alert>.Action>)
        enum Alert: Equatable {
            case installAndRelaunch
        }
    }
    
    fileprivate enum CancelID: Hashable {
        case checkForUpdatesInBackgroundOnce
        case checkingForUpdates
        case downloadUpdate
    }

    @Dependency(\.softwareUpdateClient) var softwareUpdateClient

    init() {
    }

    /**
     If this succeeds we will get restarted with -installUpgradeCompleted path\_to\_update

     Fast debug
     /Users/kdeda/Developer/build/Debug/WhatSize.app/Contents/MacOS/WhatSize -standardLog true -UpdateInfo.checkForUpdatesAutomatically true -UpdateInfo.installUpdateDebug true
     /Applications/WhatSize.app/Contents/MacOS/WhatSize -standardLog true -installUpgradeCompleted /Users/kdeda/Desktop/Packages/WhatSize_8.1.0/com.id-design.v8.whatsizehelper
     */
    fileprivate func installAndRelaunch(_ state: State) -> Effect<Action> {
        /// /Applications/WhatSize.app
        let applicationPath = Bundle.main.bundlePath
        /// A path to a temporary folder that should contain the WhatSize.pkg and the UpdateInfo.json we are applying
        let pkgFilePath = state.update.downloadPKGURL.path

        return .run { send in
            await send(.delegate(.completed))
            // hang on a tinny bit
            try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * UInt64(50))
            await NSApp.hide(nil)
            
            await softwareUpdateClient.installUpgrade(
                UpdateInfo.installUpdateDebug ? URL.home.appendingPathComponent("Desktop/Packages/WhatSize_8.1.0/WhatSize.pkg").path : pkgFilePath,
                applicationPath
            )
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

#if DEBUG
                let frequency = 5 //in seconds
#else
                let frequency = 60 * 60 // in seconds
#endif
                Log4swift[Self.self].info(".checkForUpdatesInBackgroundOnce: frequency: '\(state.settings.updateInterval.name)' lastCheck: '\(state.settings.lastCheckString) 'nextCheck: '\(state.settings.nextCheckDate.stringWithDateFormatter(Settings.dateFormatter))' isInteracting: '\(isInteracting)' shouldCheck: '\(shouldCheck)'")
                return .run { send in
                    if !isInteracting && shouldCheck {
                        if let update = await softwareUpdateClient.checkForUpdates() {
                            await send(.checkForUpdatesDidEnd(update, true))
                            return
                        }
                        // we will re-try in a bit
                        Log4swift[Self.self].error(".checkForUpdatesInBackgroundOnce handle failure to fetch: 'NOOP'")
                    }
                    try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * UInt64(1000 * frequency)) // sleep for a bit and retry
                    await send(.checkForUpdatesInBackgroundOnce)
                }
                .cancellable(id: CancelID.checkForUpdatesInBackgroundOnce, cancelInFlight: true)

            case .checkForUpdates:
                state.installStep = .checkForUpdates

                if UpdateInfo.installUpdateDebug {
                    // quick debuging
                    state.installStep = .installAndRelaunch

                    return .run { send in
                        Task.cancel(id: CancelID.checkForUpdatesInBackgroundOnce)
                        await send(.delegate(.started))
                        try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * UInt64(1250))
                        await send(.installAndRelaunch)
                    }
                }

                return .run { send in
                    Task.cancel(id: CancelID.checkForUpdatesInBackgroundOnce)
                    await send(.delegate(.started))
                    if let update = await softwareUpdateClient.checkForUpdates() {
                        await send(.checkForUpdatesDidEnd(update, false))
                        return
                    }
                    try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 250)
                    await send(.delegate(.failedToFetchUpdate))
                }
                .cancellable(id: CancelID.checkingForUpdates, cancelInFlight: true)

            case .cancelCheckForUpdates:
                return .run { send in
                    await send(.delegate(.cancelled))
                    Task.cancel(id: CancelID.checkingForUpdates)
                }

            case let .checkForUpdatesDidEnd(update, isBackground):
                Log4swift[Self.self].info(".checkForUpdatesDidEnd buildNumber: '\(update.buildNumber)', shortVersion: '\(update.shortVersion)', appVersion: '\(Bundle.main.appVersion.shortVersion)', datePublished: '\(update.datePublished)', downloadByteCount: '\(update.downloadByteCount.decimalFormatted)', isBackground: '\(isBackground ? "yuup" : "noop")'")

                state.update = update
                state.settings.lastCheckDate = Date()
                Settings.lastSaved = state.settings
#if DEBUG
                let buildNumber = Bundle.main.appVersion.buildNumber
#else
                let buildNumber = Bundle.main.appVersion.buildNumber
#endif

                if isBackground {
                    // we are comming from a background fetch
                    // be quiet unless a new update is found
                    if update.buildNumber > buildNumber {
                        // onto the next step
                        // become visible
                        state.installStep = .displayNewVersion
                        return .send(.delegate(.started))
                    }

                    // schedule the new fetch
                    return .send(.checkForUpdatesInBackgroundOnce)
                }

                // user initiated
                if update.buildNumber > buildNumber {
                    // onto the next step
                    // we should already be visible
                    state.installStep = .displayNewVersion
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
                        try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 250) // let it breathe a bit
                        if !update.downloadPKGURL.fileExist {
                            Log4swift[Self.self].error(".downloadUpdate: failed to create: '\(update.downloadPKGURL.path)'")
                            await send(.delegate(.completed))
                            return
                        }

                        // Did we get is what we were supposed
                        var freshUpdate = update

                        freshUpdate.downloadSHA256 = update.downloadPKGURL.sha256
                        freshUpdate.downloadByteCount = Int(update.downloadPKGURL.logicalSize)
                        if !freshUpdate.validateSignatures(update) {
                            Log4swift[Self.self].error(".downloadUpdate: failed to assert the signatures. This should not happen.")
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
                        ButtonState.doNotAskAgain()
                        ButtonState(action: .installAndRelaunch) {
                            TextState(.okButtonTitle)
                        }
                        ButtonState(role: .cancel) {
                            TextState(.cancelButtonTitle)
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
                let update = try? UpdateInfo.jsonDecoder.decode(UpdateInfo.self, from: data)

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
