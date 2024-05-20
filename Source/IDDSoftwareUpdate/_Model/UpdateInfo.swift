//
//  UpdateInfo.swift
//  IDDSoftwareUpdate
//
//  Created by Klajd Deda on 4/3/24.
//  Copyright (C) 1997-2024 id-design, inc. All rights reserved.
//

import Foundation
import IDDSwiftUI
import ComposableArchitecture

public struct UpdateInfo: Equatable, Codable {
    // this should match to ../git.id-design.com/installer_tools/xchelper/xchelper/WhatSize8/Project.json
    internal static let updateCipherPassword = "6FA668D8-9839-47F2-93E2-4F9A9D8E61CF"
    /**
     fast debug turn around
     -UpdateInfo.hostURL http://local.whatsizemac.com
     */
    public static var hostURL: URL = {
        @Dependency(\.softwareUpdateClient) var softwareUpdateClient
        return softwareUpdateClient.websiteURL()
    }()

    /**
     fast debug turn around
     -UpdateInfo.checkForUpdatesAutomatically true
     */
    public static var checkForUpdatesAutomatically: Bool = {
        if UserDefaults.standard.bool(forKey: "UpdateInfo.checkForUpdatesAutomatically") {
            return true
        }
        return false
    }()

    public static var installUpdateDebug: Bool = {
        if UserDefaults.standard.bool(forKey: "UpdateInfo.installUpdateDebug") {
            return true
        }
        return false
    }()

    internal static let updatesCipher = Cipher(password: updateCipherPassword, version: 1)
    public static let jsonDecoder: JSONDecoder = {
        let rv = JSONDecoder()

        rv.dateDecodingStrategy = .formatted(Date.defaultFormatter)
        rv.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "+Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return rv
    }()
    public static let jsonEncoder: JSONEncoder = {
        let rv = JSONEncoder()

        rv.dateEncodingStrategy = .formatted(Date.defaultFormatter)
        rv.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "+Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        rv.outputFormatting = [.prettyPrinted, .sortedKeys]
        return rv
    }()

    /**
     Apr 2, 2024 at 11:48:33 PM
     The default timeZone on DateFormatter is the device’s local time zone.
     */
    public static let localDateFormatter: DateFormatter = {
        let rv = DateFormatter()

        rv.dateStyle = .medium
        rv.timeStyle = .medium
        return rv
    }()

    public static let empty: Self = .init(
        buildNumber: 0,
        datePublished: .distantFuture,
        downloadByteCount: 19582879,
        downloadSHA256: "",
        downloadURL: Self.hostURL.appendingPathComponent("software/whatsize8/whatsize_8.0.1.pkg"),
        releaseNotesURL: Self.hostURL.appendingPathComponent("software/whatsize8/release/notes.html"),
        shortVersion: "1.0.1",
        signature: ""
    )

    public let buildNumber: Int
    public let datePublished: Date
    public var downloadByteCount: Int
    public var downloadSHA256: String
    public var downloadURL: URL
    public var releaseNotesURL: URL
    public let shortVersion: String
    public var signature: String

    public init(buildNumber: Int,
         datePublished: Date,
         downloadByteCount: Int,
         downloadSHA256: String,
         downloadURL: URL,
         releaseNotesURL: URL,
         shortVersion: String,
         signature: String
    ) {
        self.buildNumber = buildNumber
        self.datePublished = datePublished
        self.downloadByteCount = downloadByteCount
        self.downloadSHA256 = downloadSHA256
        self.downloadURL = downloadURL
        self.releaseNotesURL = releaseNotesURL
        self.shortVersion = shortVersion
        self.signature = signature
    }

    public var datePublishedString: String {
        Self.localDateFormatter.string(from: datePublished)
    }

    /**
     We will not know until the bytes from downloadURL have been downloaded.
     Return true if this payload or the bytes it represents has been tempered.
     */
    public var wasTempered: Bool {
        var copy = self

        copy.signature = UpdateInfo.updateCipherPassword // placeholder, hard to guess for someone willing to temper these
        let jsonData = (try? UpdateInfo.jsonEncoder.encode(copy)) ?? Data()
        let json = String(data: jsonData, encoding: .utf8) ?? ""
        let decrypted = UpdateInfo.updatesCipher.decrypt(self.signature)

        if decrypted != json {
            Log4swift[Self.self].error("Failed to assert the signatures. This should not happen.")
            return true
        }

        return false
    }

    var downloadRootURL: URL {
        URL.temporaryDirectory.appendingPathComponent("whatsize_update_\(self.buildNumber)")
    }

    var downloadPKGURL: URL {
        downloadRootURL.appendingPathComponent("WhatSize.pkg")
    }

    var jsonFileURL: URL {
        downloadRootURL.appendingPathComponent("UpdateInfo.json")
    }

    /**
     Adjust urls to be of same origin as url
     */
    var updatingHostURL: Self {
        var copy = self
        
        copy.downloadURL = Self.hostURL.appendingPathComponent(self.downloadURL.path)
        copy.releaseNotesURL = Self.hostURL.appendingPathComponent(self.releaseNotesURL.path)
        return copy
    }

    /**
     These should match
     */
    func validateSignatures(_ downloadedInstance: Self) -> Bool {
        var lhs = self
        var rhs = downloadedInstance

        lhs.signature = Self.updateCipherPassword // placeholder, hard to guess for someone willing to temper these
        rhs.signature = Self.updateCipherPassword // placeholder, hard to guess for someone willing to temper these

        let lhs_jsonData = (try? Self.jsonEncoder.encode(lhs)) ?? Data()
        let lhs_json = String(data: lhs_jsonData, encoding: .utf8) ?? ""

        let rhs_jsonData = (try? Self.jsonEncoder.encode(rhs)) ?? Data()
        let rhs_json = String(data: rhs_jsonData, encoding: .utf8) ?? ""

        return lhs_json == rhs_json
    }

}
