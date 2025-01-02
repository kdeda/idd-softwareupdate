//
//  InstallStep.swift
//  idd-softwareupdate
//
//  Created by Klajd Deda on 5/17/24.
//  Copyright (C) 1997-2025 id-design, inc. All rights reserved.
//

import Foundation

public enum InstallStep: Equatable, Sendable {
    case none
    case checkForUpdates
    case displayNewVersion
    case downloadUpdate
    case installAndRelaunch
    case installUpgradeCompleted
    case settings
    case uptoDate
}
