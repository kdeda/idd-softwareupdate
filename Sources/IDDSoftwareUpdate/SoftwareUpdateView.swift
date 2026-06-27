//
//  SoftwareUpdateView.swift
//  idd-softwareupdate
//
//  Created by Klajd Deda on 4/3/24.
//  Copyright (C) 1997-2026 id-design, inc. All rights reserved.
//

import Foundation
import SwiftUI
import Log4swift
@preconcurrency import IDDSwiftUI
import ComposableArchitecture
import WebKit

fileprivate extension View {
    /// Applies a modifier conditionally based on a runtime availability check.
    @ViewBuilder
    func modify<Content: View>(@ViewBuilder _ transform: (Self) -> Content) -> Content {
        transform(self)
    }
}

fileprivate extension View {
    /**
     Hack the ffing thing, or it does not resize the window
     Tells the AppKit sheet window to remeasure without breaking identity
     */
    func layoutWindow(onChangeOf value: some Equatable) -> some View {
        self.onChange(of: value) { _ in
            if #available(macOS 15.0, *) {
                // Safely schedules a window layout update on the next runloop turn
                DispatchQueue.main.async {
                    //  Log4swift["SoftwareUpdateView"].info("mainWindow: '\(NSApp.mainWindow?.contentView?.window)'")
                    //  Log4swift["SoftwareUpdateView"].info("keyWindow: '\(NSApp.keyWindow)'")
                    //  Log4swift["SoftwareUpdateView"].info("mainWindow: '\(NSApp.mainWindow?.title)'")
                    //  Log4swift["SoftwareUpdateView"].info("keyWindow: '\(NSApp.keyWindow?.title)'")

                    guard let window = NSApp.keyWindow
                    else { return }

                    // Log4swift["SoftwareUpdateView"].info("keyWindow: '\(window.contentView?.frame)'")
                    // 1. Force the window's layout engine to recalculate its intrinsic content size
                    window.contentViewController?.view.needsLayout = true

                    // 2. Tell the window to adjust its frame to match the newly calculated view size
                    if let minSize = window.contentView?.fittingSize {
                        // Smoothly animate the window frame to the new fitting size
                        // Log4swift["SoftwareUpdateView"].info("keyWindow: '\(minSize)'")
                        window.setContentSize(minSize)
                    }
                }
            }
        }
    }
}

public struct SoftwareUpdateView: View {
    @Perception.Bindable var store: StoreOf<SoftwareUpdate>
    @Dependency(\.softwareUpdateClient) var softwareUpdateClient

    fileprivate struct UpdatesView<Content, Buttons>: View where Content: View, Buttons: View {
        var title: String
        var content: () -> Content
        var buttons: () -> Buttons

        init(
            _ title: String,
            @ViewBuilder content: @escaping () -> Content,
            @ViewBuilder buttons: @escaping () -> Buttons
        ) {
            self.title = title
            self.content = content
            self.buttons = buttons
        }

        var body: some View {
            VStack(spacing: 10) {
                WithPerceptionTracking {
                    VStack(spacing: 10) {
                        HStack {
                            Text(title)
                                .font(.title2.weight(.semibold))
                            Spacer()
                        }
                        .padding(.bottom, 10)
                        content()
                        buttons()
                            .padding(.top, 20)
                    }
                    // .border(.yellow)
                }
            }
        }
    }

    @ViewBuilder
    func checkForUpdates() -> some View {
        UpdatesView("Checking for updates...") {
            ProgressView()
                .progressViewStyle(LinearProgressViewStyle())
        } buttons: {
            HStack { // buttons
                Spacer()
                Button(action: { store.send(.cancelCheckForUpdates) }) {
                    Text("Cancel")
                        .padding(.horizontal, 6)
                }
            }
        }
        .frame(width: 380)
    }

    @ViewBuilder
    func displayNewVersion() -> some View {
        UpdatesView("A new version of WhatSize is available!") {
            VStack(spacing: 10) {
                HStack {
                    Text("WhatSize \(store.update.shortVersion) is now available. You have \(Bundle.main.appVersion.shortVersion). Would you like to download it now?")
                        .font(.callout)
                    Spacer()
                }
                HStack {
                    Text("Release Notes:")
                        .font(.callout.weight(.bold))
                    Spacer()
                }
            }
            ZStack {
                VStack {
                    HStack {
                        Text("Fetching data ...")
                            .font(.callout)
                        Spacer()
                    }
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle())
                        .opacity(store.inFlightLoadingURL ? 1.0 : 0.0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing) // <-- Push to top right
                .padding(20)
                
                /**
                 TODO: implement the dark mode support
                 It should be done at the CSS for the notes.html
                 */
                WebView(url: store.update.releaseNotesURL, onLoadComplete: {
                    store.send(.setInFlightLoadingURL(false))
                })
                //   .modify { view in
                //       if #available(macOS 12.0, *) {
                //           view.background(.white.opacity(0.8))
                //       }
                //   }
                .border(.gray.opacity(0.4))
            }
        } buttons: {
            HStack { // buttons
                Button(action: { store.send(.skipThisVersion) }) {
                    Text("Skip This Version")
                        .padding(.horizontal, 6)
                }
                .disabled(store.inFlightLoadingURL)
                Spacer()

                Button(action: { store.send(.remindMeLater) }) {
                    Text("Remind Me Later")
                        .padding(.horizontal, 6)
                }
                .disabled(store.inFlightLoadingURL)
                .help("Will postpone checking for new week.")

                Button(action: { store.send(.downloadUpdate) }) {
                    Text("Install Update")
                        .padding(.horizontal, 6)
                }
                .disabled(store.inFlightLoadingURL)
                .help("Will download the update.")
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(minWidth: 480, idealWidth: 480, maxWidth: 800)
        .frame(minHeight: 380, idealHeight: 380, maxHeight: 600)
    }

    @ViewBuilder
    func downloadUpdate() -> some View {
        UpdatesView("Downloading...") {
            ProgressView(value: Double(store.downloadedByteCount), total: Double(store.update.downloadByteCount))
                .progressViewStyle(LinearProgressViewStyle())
        } buttons: {
            HStack { // buttons
                Text("\(store.downloadedByteCount.compactFormatted) of \(store.update.downloadByteCount.compactFormatted)")
                Spacer()
                Button(action: { store.send(.cancelDownloadUpdate) }) {
                    Text("Cancel")
                        .padding(.horizontal, 6)
                }
            }
        }
        .frame(width: 380)
    }

    @ViewBuilder
    func installAndRelaunch() -> some View {
        UpdatesView("Ready to install.") {
            ProgressView(value: 1, total: 1)
                .progressViewStyle(LinearProgressViewStyle())
        } buttons: {
            HStack {
                Spacer()

                Button(action: { store.send(.installAndRelaunch) }) {
                    Text("Install and Relaunch")
                        .padding(.horizontal, 6)
                }
                .help("Will install the update and relaunch this application.")
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 380)
    }

    @ViewBuilder
    func settings() -> some View {
        let labelWidth: Double = 140

        UpdatesView("Settings") {
            RowLabelView(
                label: "Check for Updates:",
                width: labelWidth,
                content: {
                    Toggle(isOn: $store.settings.automatically.sending(\.setAutomatically)) {
                        Text("Automatically")
                    }
                }
            )

            RowLabelView(
                label: "Update Interval:",
                width: labelWidth,
                content: {
                    PickerView(
                        items: UpdateInterval.allCases,
                        selectedItem: $store.settings.updateInterval.sending(\.setUpdateInterval)
                    ) {
                        Text($0.name)
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 120)
                }
            )

            RowLabelView(
                label: "Last Check Time:",
                width: labelWidth,
                content: {
                    HStack {
                        Text("\(store.settings.lastCheckString)")
                        Spacer()
                    }
                }
            )
        } buttons: {
            HStack { // buttons
                Spacer()
                Button(action: { store.send(.dismissSettings) }) {
                    Text("OK")
                        .padding(.horizontal, 6)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 380)
    }

    @ViewBuilder
    func uptoDate() -> some View {
        UpdatesView("You’re up-to-date!") {
            HStack {
                Text("WhatSize \(store.update.shortVersion) is currently the newest version available.")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.callout)
                Spacer()
            }
        } buttons: {
            HStack { // buttons
                Spacer()
                Button(action: { store.send(.showSettings) }) {
                    Text("Settings")
                        .padding(.horizontal, 6)
                }

                Button(action: { store.send(.cancelCheckForUpdates) }) {
                    Text("OK")
                        .padding(.horizontal, 6)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 380)
    }

    @ViewBuilder
    func upgradeCompleted() -> some View {
        UpdatesView("Upgrade Completed.") {
            HStack(spacing: 10) {
                Text("WhatSize \(store.update.shortVersion) was just installed.")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.callout)
                Spacer()
            }
        } buttons: {
            HStack { // buttons
                Spacer()
                Button(action: { store.send(.installUpgradeDismiss) }) {
                    Text("OK")
                        .padding(.horizontal, 6)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 380)
    }

    public init(store: StoreOf<SoftwareUpdate>) {
        self.store = store
    }
    
    public var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 20) {
                    Image(nsImage: softwareUpdateClient.appIconImage())
                        .resizable()
                        .frame(width: 64, height: 64)
                        // .border(.yellow)

                    switch store.installStep {
                    case .none:                    EmptyView()
                    case .checkForUpdates:         checkForUpdates()
                    case .displayNewVersion:       displayNewVersion()
                    case .downloadUpdate:          downloadUpdate()
                    case .installAndRelaunch:      installAndRelaunch()
                    case .installUpgradeCompleted: upgradeCompleted()
                    case .settings:                settings()
                    case .uptoDate:                uptoDate()
                    }
                }
                .padding(.top, 5)
            }
            .padding(20)
            .layoutWindow(onChangeOf: store.installStep)
            .animation(.default, value: store.installStep)
            .onDisappear(perform: {
                store.send(.cancelCheckForUpdates)
            })
            .dnsAlert($store.scope(state: \.alert, action: \.alert))
        }
    }
}

@MainActor
fileprivate func newStore() -> StoreOf<SoftwareUpdate> {
    Log4swift.configureCompactSettings()
    Log4swift.configure(fileLogConfig: .none)

    prepareDependencies {
        //        $0.softwareUpdateClient.websiteURL = { useTestServer in
        //            guard let hostURLString = UserDefaults.standard.string(forKey: "AppDefaults.websiteURL"),
        //                  let hostURL = URL(string: hostURLString)
        //            else {
        //                Log4swift["SoftwareUpdateView"].info(function: "websiteURL", "useTestServer: '\(useTestServer)'")
        //                return URL(string: useTestServer ? "https://test.whatsizemac.com" : "https://www.whatsizemac.com")!
        //            }
        //            return hostURL
        //        }
        /**
         Assumes whatsize8 is installed relative to us
         ~/Developer/git.id-design.com/spm/whatsize8
         ~/Developer/git.id-design.com/spm/idd-softwareupdate
         */
        $0.softwareUpdateClient.appIconImage = {
            let fileURL = URL.init(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("whatsize8/WhatSize/AppIconOriginal.png")

            Log4swift["SoftwareUpdateView"].info("fileURL: '\(fileURL.path)'")
            let data = try? Data.init(contentsOf: fileURL)
            return NSImage.init(data: data ?? Data()) ?? NSImage()
        }
    }

    var state = SoftwareUpdate.State()

    state.useTestServer = true
    /**
     Comment uncomment the following to see
     */
    state.installStep = .downloadUpdate
    state.installStep = .installAndRelaunch
    state.installStep = .installUpgradeCompleted
    state.installStep = .checkForUpdates
    state.installStep = .uptoDate
    state.installStep = .settings
    state.installStep = .displayNewVersion

    return Store(
        initialState: state,
        reducer: SoftwareUpdate.init
    )
}

/**
 xcode 26.2 preview work on the mac
 but here you will need to extra configure the dependency
 */
#Preview("SoftwareUpdateView - Light") {
    let store = newStore()

    return SoftwareUpdateView(store: store)
        .onAppear(perform: {
            Log4swift["SoftwareUpdateView"].info("onAppear")
            store.send(.appDidStart)
        })
        .preferredColorScheme(.light)
}

#Preview("SoftwareUpdateView - Dark") {
    let store = newStore()

    return SoftwareUpdateView(store: store)
        .onAppear(perform: {
            Log4swift["SoftwareUpdateView"].info("onAppear")
            store.send(.appDidStart)
        })
        .preferredColorScheme(.dark)
}
