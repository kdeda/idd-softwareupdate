//
//  WebView.swift
//  IDDSoftwareUpdate
//
//  Created by Klajd Deda on 4/3/24.
//  Copyright (C) 1997-2024 id-design, inc. All rights reserved.
//

import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()

        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
}
