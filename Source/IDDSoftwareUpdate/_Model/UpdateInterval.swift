//
//  UpdateInterval.swift
//  IDDSoftwareUpdate
//
//  Created by Klajd Deda on 5/17/24.
//  Copyright (C) 1997-2024 id-design, inc. All rights reserved.
//

import Foundation

enum UpdateInterval: String, CaseIterable, Equatable, Hashable, Identifiable, Codable {
    case daily
    case weekly
    case monthly

    var id: String {
        self.rawValue
    }

    var name: String {
        switch self {
        case .daily:   "Daily"
        case .weekly:  "Weekly"
        case .monthly: "Monthly"
        }
    }
}
