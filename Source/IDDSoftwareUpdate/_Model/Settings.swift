//
//  Settings.swift
//  idd-softwareupdate
//
//  Created by Klajd Deda on 5/17/24.
//  Copyright (C) 1997-2025 id-design, inc. All rights reserved.
//

import Foundation
import IDDSwift

extension SoftwareUpdate {
    public struct Settings: Equatable, Codable, Sendable {
        public static let defaultItem = Settings()
        public static var lastSaved: Settings {
            get {
                @UserDefaultsValue(.defaultItem, forKey: "CheckForUpdates.Settings.lastSaved")
                var lastSaved: Settings

                return _lastSaved.wrappedValue
            }
            set {
                @UserDefaultsValue(.defaultItem, forKey: "CheckForUpdates.Settings.lastSaved")
                var lastSaved: Settings

                _lastSaved.wrappedValue = newValue
            }
        }

        internal static let dateFormatter: DateFormatter = {
            var rv = DateFormatter()

            // https://www.advancedswift.com/date-formatter-cheatsheet-formulas-swift/
            // // formatter.timeZone = TimeZone(identifier: "EDT")
            // rv.timeZone = .current
            // rv.dateFormat = "MMMM d, yyyy HH:mm a"
            rv.dateStyle = .long
            rv.timeStyle = .short
            rv.doesRelativeDateFormatting = true
            return rv
        }()

        public var automatically: Bool = true
        public var updateInterval: UpdateInterval = .daily
        public var skipVersion: Int = 0
        /**
         Will contain the stamp of the last successfull check
         */
        public var lastCheckDate: Date = .distantPast

        public init() {
        }

        public var lastCheckString: String {
            lastCheckDate.stringWithDateFormatter(Self.dateFormatter)
        }

        /**
         Return the next day to check for updates.

         For example if the lastCheckDate was 'May 15, 2024 2:30 PM' and the updateInterval is 'daily' we should get "May 16, 2024 2:30 PM"
         For example if the lastCheckDate was 'May 15, 2024 2:30 PM' and the updateInterval is 'weekly' we should get "May 22, 2024 2:30 PM"

         To change it for testing:
         defaults write com.id-design.v8.whatsize.plist CheckForUpdates.Settings.lastSaved.json -string '{"skipVersion" : 8100, "automatically" : true,  "updateInterval" : "daily",  "lastCheckDate" : "2024-05-16T16:10:50Z"}'
         defaults write com.id-design.v8.whatsize.plist CheckForUpdates.Settings.lastSaved.json -string '{"skipVersion" : 8100, "automatically" : true,  "updateInterval" : "weekly",  "lastCheckDate" : "2024-05-16T16:10:50Z"}'
         */
        public var nextCheckDate: Date {
            guard lastCheckDate != .distantPast
            else { return Date() }

            switch updateInterval {
            case .daily:
                let next = Calendar.current.date(byAdding: .day, value: 1, to: lastCheckDate)
                return next ?? lastCheckDate.date(shiftedByDays: 1)

            case .weekly:
                let next = Calendar.current.date(byAdding: .day, value: 7, to: lastCheckDate)
                return next ?? lastCheckDate.date(shiftedByDays: 7)

            case .monthly:
                let next = Calendar.current.date(byAdding: .month, value: 1, to: lastCheckDate)
                return next ?? lastCheckDate.date(shiftedByDays: 30)
            }
        }

        /**
         Basically if the nextCheckDate falls in the past do check please as soon as possible.
         */
        public var shouldCheckForUpdates: Bool {
            Int(nextCheckDate.timeIntervalSinceNow) <= 0
        }

    }
}
