//
//  URL+SHA266.swift
//  idd-softwareupdate
//
//  Created by Klajd Deda on 12/17/24.
//  Copyright (C) 1997-2024 id-design, inc. All rights reserved.
//

import Foundation
import Log4swift
import Crypto

public extension URL {
    /**
     Will return the long version eg:
     `6E339440FF55F55F-4EE022FE86-3573B8AB6267-5264312227CA-E000E94DC5EA75`
     */
    var sha256With68Chars: String {
        guard let handle = try? FileHandle(forReadingFrom: self)
        else { return "" }
        var hasher = SHA256()
        
        while autoreleasepool(invoking: {
            let nextChunk = handle.readData(ofLength: SHA256.blockByteCount)
            guard !nextChunk.isEmpty
            else { return false }
            
            hasher.update(data: nextChunk)
            return true
        }) { }
        let digest = hasher.finalize()
        
        var tokens = digest.map { String(format: "%02x", $0) }
        
        if tokens.count == 32 {
            tokens.insert("-", at: 8)
            tokens.insert("-", at: 14)
            tokens.insert("-", at: 21)
            tokens.insert("-", at: 28)
        }
        
        return tokens.joined(separator: "").uppercased()
    }
}
