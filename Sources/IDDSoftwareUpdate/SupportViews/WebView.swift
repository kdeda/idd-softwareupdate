//
//  WebView.swift
//  idd-softwareupdate
//
//  Created by Klajd Deda on 4/3/24.
//  Copyright (C) 1997-2026 id-design, inc. All rights reserved.
//

import SwiftUI
import Log4swift
import WebKit

struct WebView: NSViewRepresentable {
    let url: URL
    let onLoadComplete: () -> Void

    // 1. Create the Coordinator to act as the WKNavigationDelegate
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: .nanoseconds(milliseconds: 1250))
                parent.onLoadComplete()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()

        // 2. Assign the coordinator as the navigation delegate
        webView.navigationDelegate = context.coordinator

        /**
         Blast all caches.
         https://stackoverflow.com/questions/27105094/how-to-remove-cache-in-wkwebview
         */
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date(timeIntervalSince1970: 0),
            completionHandler: {}
        )
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url == url || webView.isLoading {
            return
        }

        let request = URLRequest(url: url)
        Log4swift[Self.self].info("url: '\(url.absoluteString)'")
        webView.load(request)
    }
}
