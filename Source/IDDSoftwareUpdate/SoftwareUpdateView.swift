//
//  SoftwareUpdateView.swift
//  IDDSoftwareUpdate
//
//  Created by Klajd Deda on 4/3/24.
//  Copyright (C) 1997-2024 id-design, inc. All rights reserved.
//

import Foundation
import SwiftUI
import IDDSwiftUI
import ComposableArchitecture
import WebKit

struct SoftwareUpdateView: View {
    @Perception.Bindable var store: StoreOf<SoftwareUpdate>

    fileprivate struct UpdatesView<Content>: View where Content: View {
        var title: String
        var content: () -> Content

        init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
            self.title = title
            self.content = content
        }

        var body: some View {
            VStack(spacing: 10) {
                WithPerceptionTracking {
                    if !title.isEmpty {
                        HStack {
                            Text(title)
                                .fontWeight(.bold)
                            Spacer()
                        }
                    }
                    content()
                }
            }
        }
    }

    @ViewBuilder
    func checkForUpdates() -> some View {
        UpdatesView("Checking for updates...") {
            ProgressView()
                .progressViewStyle(LinearProgressViewStyle())
            HStack {
                Spacer()
                Button(action: { store.send(.cancelCheckForUpdates) }) {
                    Text("Cancel")
                        .padding(.horizontal, 6)
                }
            }
        }
        .frame(width: 320)
        // .border(.yellow)
    }

    @ViewBuilder
    func displayNewVersion() -> some View {
        UpdatesView("A new version of WhatSize is available!") {
            HStack {
                Text("WhatSize \(store.update.shortVersion) is now available. You have \(Bundle.main.appVersion.shortVersion). Would you like to download it now?")
                    .font(.callout)
                Spacer()
            }
            HStack {
                Text("Release Notes:")
                    .font(.callout)
                    .fontWeight(.bold)
                Spacer()
            }
            /**
             TODO: implement the dark mode support
             It should be done at the CSS for the notes.html
             */
            WebView(url: store.update.releaseNotesURL)
                .background(.white.opacity(0.8))
                .border(.gray.opacity(0.4))
        }
        .frame(minWidth: 540, idealWidth: 540)
        .frame(minHeight: 320, idealHeight: 320)
    }

    @ViewBuilder
    func downloadUpdate() -> some View {
        UpdatesView("Downloading...") {
            ProgressView(value: Double(store.downloadedByteCount), total: Double(store.update.downloadByteCount))
                .progressViewStyle(LinearProgressViewStyle())
            HStack {
                Text("\(store.downloadedByteCount.compactFormatted) of \(store.update.downloadByteCount.compactFormatted)")
                Spacer()

                Button(action: { store.send(.cancelDownloadUpdate) }) {
                    Text("Cancel")
                        .padding(.horizontal, 6)
                }
            }
        }
        .frame(width: 320)
    }

    @ViewBuilder
    func installAndRelaunch() -> some View {
        UpdatesView("Ready to install.") {
            ProgressView(value: 1, total: 1)
                .progressViewStyle(LinearProgressViewStyle())
            HStack {
                Spacer()

                Button(action: { store.send(.installAndRelaunch) }) {
                    Text("Install and Relaunch")
                        .padding(.horizontal, 6)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 320)
    }

    @ViewBuilder
    func settings() -> some View {
        let labelWidth: Double = 140

        UpdatesView("") {
            VStack(alignment: .leading, spacing: 10) {
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
            }

            HStack {
                Spacer()
                Button(action: { store.send(.dismissSettings) }) {
                    Text("OK")
                        .padding(.horizontal, 6)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 320)
        // .border(.yellow)
    }

    @ViewBuilder
    func uptoDate() -> some View {
        UpdatesView("You’re up-to-date!") {
            HStack {
                Text("WhatSize \(store.update.shortVersion) is currently the newest version available.")
                // fuck it apple, this does not size properly, it wraps after the word `newest`
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.callout)
                Spacer()
            }
            HStack {
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
        .frame(width: 320)
        // .border(.yellow)
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
            HStack {
                Spacer()

                Button(action: { store.send(.installUpgradeDismiss) }) {
                    Text("OK")
                        .padding(.horizontal, 6)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 320)
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 20) {
                    Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                        .resizable()
                        .frame(width: 64, height: 64)

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
                // .border(.yellow)

                switch store.installStep {
                case .none:                    EmptyView()
                case .checkForUpdates:         EmptyView()
                case .displayNewVersion:
                    // bottom buttons
                    HStack(spacing: 20) {
                        Button(action: { store.send(.skipThisVersion) }) {
                            Text("Skip This Version")
                                .padding(.horizontal, 6)
                        }
                        Spacer()
                        Button(action: { store.send(.remindMeLater) }) {
                            Text("Remind Me Later")
                                .padding(.horizontal, 6)
                        }
                        Button(action: { store.send(.downloadUpdate) }) {
                            Text("Install Update")
                                .padding(.horizontal, 6)
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.leading, 84) // this is the space taken by the appIcon
                    // .border(.yellow)
                case .downloadUpdate:          EmptyView()
                case .installAndRelaunch:      EmptyView()
                case .installUpgradeCompleted: EmptyView()
                case .settings:                EmptyView()
                case .uptoDate:                EmptyView()
                }
            }
            .padding(.top, 10)
            // .frame(minWidth: 600, idealWidth: 600)
            // .frame(minHeight: 400, idealHeight: 400)
            .padding(20)
            .onDisappear(perform: {
                store.send(.cancelCheckForUpdates)
            })
            .dnsAlert($store.scope(state: \.alert, action: \.alert))
        }
    }
}

fileprivate func store() -> StoreOf<SoftwareUpdate> {
    var state = SoftwareUpdate.State()

    state.installStep = .displayNewVersion
    state.installStep = .downloadUpdate
    state.installStep = .installAndRelaunch
    state.installStep = .installUpgradeCompleted
    state.installStep = .checkForUpdates
    state.installStep = .uptoDate
    state.installStep = .settings

    return Store(
        initialState: state,
        reducer: SoftwareUpdate.init
    )
}

#Preview("SoftwareUpdateView - Light") {
    SoftwareUpdateView(store: store())
        .preferredColorScheme(.light)
}

#Preview("SoftwareUpdateView - Dark") {
    SoftwareUpdateView(store: store())
        .preferredColorScheme(.dark)
}
