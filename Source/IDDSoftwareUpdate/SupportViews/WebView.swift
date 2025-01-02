//
//  WebView.swift
//  idd-softwareupdate
//
//  Created by Klajd Deda on 4/3/24.
//  Copyright (C) 1997-2025 id-design, inc. All rights reserved.
//

import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()

        /**
         Blast all caches.
         https://stackoverflow.com/questions/27105094/how-to-remove-cache-in-wkwebview
         */
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0), completionHandler: {})
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
}
