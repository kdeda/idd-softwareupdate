//
//  UpdateInfo.swift
//  idd-softwareupdate
//
//  Created by Klajd Deda on 4/3/24.
//  Copyright (C) 1997-2025 id-design, inc. All rights reserved.
//

import Foundation
@preconcurrency import IDDSwiftUI
import ComposableArchitecture

public struct UpdateInfo: Equatable, Sendable {
    /**
     this should match to ../git.id-design.com/installer_tools/xchelper/xchelper/WhatSize8/Project.json
    */
    internal static let updateCipherPassword = "6FA668D8-9839-47F2-93E2-4F9A9D8E61CF"
    internal static let boobs                = "80088008-8008-8008-8008-800800008008"

    /**
     fast debug turn around
     -UpdateInfo.hostURL http://local.whatsizemac.com
     */
    public static func hostURL(_ useTestServer: Bool) -> URL {
        @Dependency(\.softwareUpdateClient) var softwareUpdateClient
        return softwareUpdateClient.websiteURL(useTestServer)
    }

    /**
     fast debug turn around
     -UpdateInfo.checkForUpdatesAutomatically true
     */
    public static let checkForUpdatesAutomatically: Bool = {
        if UserDefaults.standard.bool(forKey: "UpdateInfo.checkForUpdatesAutomatically") {
            return true
        }
        return false
    }()

    public static let installUpdateDebug: Bool = {
        if UserDefaults.standard.bool(forKey: "UpdateInfo.installUpdateDebug") {
            return true
        }
        return false
    }()

    private static let updatesCipher = Cipher(password: updateCipherPassword, version: 1)
    private static let jsonDecoder: JSONDecoder = {
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
        rv.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
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
        downloadURL: Self.hostURL(false).appendingPathComponent("software/whatsize8/whatsize_8.0.1.pkg"),
        releaseNotesURL: Self.hostURL(false).appendingPathComponent("software/whatsize8/release/notes.html"),
        shortVersion: "1.0.1",
        signature: ""
    )

    public let buildNumber: Int
    /// UTC Date
    public let datePublished: Date
    public var downloadByteCount: Int
    public var downloadSHA256: String
    public var downloadURL: URL
    public var releaseNotesURL: URL
    public let shortVersion: String
    /**
     When fetching the udate instance from the internet
     This should contain the Self.updatesCipher.encrypt of self json
     Otherwise we should keep this as empty string
     */
    public var signature: String
    public var useTestServer: Bool = false

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

    init(jsonData: Data) throws {
        self = try Self.jsonDecoder.decode(UpdateInfo.self, from: jsonData)
    }

    public var datePublishedString: String {
        Self.localDateFormatter.string(from: datePublished)
    }

    /**
     We will not know until the bytes from downloadURL have been downloaded.
     Return true if this payload or the bytes it represents has been tempered.

     Make sure to not mangle the date as json, dates are UTC
     */
    public var wasTempered: Bool {
        let decrypted: Self? = {
            let decryptedJson = Self.updatesCipher.decrypt(self.signature)
            let decryptedData = decryptedJson.data(using: .utf8) ?? Data()
            let rv = try? Self.init(jsonData: decryptedData)
            
            return rv
        }()

        guard var decrypted = decrypted
        else { return true }

        var copy = self

        // ignore these two in the compare
        copy.signature = UpdateInfo.boobs
        decrypted.signature = UpdateInfo.boobs
        copy.useTestServer = false

        if decrypted != copy {
            // will not print the signature
            Log4swift[Self.self].error("Failed to assert the signatures. This should not happen.")
            Log4swift[Self.self].error(" original: '\(copy)'")
            Log4swift[Self.self].error("decrypted: '\(decrypted)'")
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
        
        copy.downloadURL = Self.hostURL(useTestServer).appendingPathComponent(self.downloadURL.path)
        copy.releaseNotesURL = Self.hostURL(useTestServer).appendingPathComponent(self.releaseNotesURL.path)
        return copy
    }

    private var jsonString: String {
        let data = (try? Self.jsonEncoder.encode(self)) ?? Data()
        let stringValue = String(data: data, encoding: .utf8) ?? ""

        return stringValue
    }

    /**
     These should match
     */
    func validateSignatures(_ downloadedInstance: Self) -> Bool {
        var lhs = self
        var rhs = downloadedInstance

        lhs.signature = Self.updateCipherPassword // placeholder, hard to guess for someone willing to temper these
        rhs.signature = Self.updateCipherPassword // placeholder, hard to guess for someone willing to temper these
        if lhs.jsonString != rhs.jsonString {
            lhs.signature = UpdateInfo.boobs
            rhs.signature = UpdateInfo.boobs

            // do not print the signature
            Log4swift[Self.self].error("Failed to assert the signatures. This should not happen.")
            Log4swift[Self.self].error(" original: '\(lhs.jsonString)'")
            Log4swift[Self.self].error("decrypted: '\(rhs.jsonString)'")
            return false
        }
        
        return true
    }

}

extension UpdateInfo: Codable {
    enum CodingKeys: String, CodingKey {
        case buildNumber
        case datePublished
        case downloadByteCount
        case downloadSHA256
        case downloadURL
        case releaseNotesURL
        case shortVersion
        case signature
    }
}
