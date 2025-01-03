//
//  UpdateInterval.swift
//  idd-softwareupdate
//
//  Created by Klajd Deda on 5/17/24.
//  Copyright (C) 1997-2025 id-design, inc. All rights reserved.
//

import Foundation

public enum UpdateInterval: String, CaseIterable, Equatable, Hashable, Identifiable, Codable, Sendable {
    case daily
    case weekly
    case monthly

    public var id: String {
        self.rawValue
    }

    public var name: String {
        switch self {
        case .daily:   "Daily"
        case .weekly:  "Weekly"
        case .monthly: "Monthly"
        }
    }
}
