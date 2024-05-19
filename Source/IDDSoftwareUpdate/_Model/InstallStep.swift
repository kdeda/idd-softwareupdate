//
//  InstallStep.swift
//  IDDSoftwareUpdate
//
//  Created by Klajd Deda on 5/17/24.
//  Copyright (C) 1997-2024 id-design, inc. All rights reserved.
//

import Foundation

enum InstallStep: Equatable {
    case none
    case checkForUpdates
    case displayNewVersion
    case downloadUpdate
    case installAndRelaunch
    case installUpgradeCompleted
    case settings
    case uptoDate
}
