//
//  MacOS11DownloadDelegate.swift
//  idd-softwareupdate
//
//  Created by Klajd Deda on 6/27/26.
//  Copyright (C) 1997-2026 id-design, inc. All rights reserved.
//

import Foundation
import Log4swift

fileprivate final class MacOS11DownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    let downloadURL: URL
    let continuation: AsyncStream<Data>.Continuation
    private var expectedContentLength: Int64 = 0
    private var buffer = Data()
    private var reportDate = Date()
    private let fpsInMilliseconds: Double = 100 // emitt no more than each 100 ms

    init(
        downloadURL: URL,
        continuation: AsyncStream<Data>.Continuation
    ) {
        self.downloadURL = downloadURL
        self.continuation = continuation
    }
    
    // 1. Grab the file size when headers are received
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.withLock {
            self.expectedContentLength = response.expectedContentLength
        }
        Log4swift[Self.self].info("expectedContentLength: '\(expectedContentLength.decimalFormatted) bytes'")
        completionHandler(.allow)
    }
    
    // 2. Track incremental chunks of data arriving safely across threads
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.withLock {
            buffer.append(data)
            guard expectedContentLength > 0 
            else { return }
            
            // Log4swift[Self.self].info("downloadedBytes: '\(buffer.count.decimalFormatted) bytes'")
            if reportDate.elapsedTimeInMilliseconds > fpsInMilliseconds {
                // Log4swift[Self.self].info("downloadedBytes: '\(buffer.count.decimalFormatted) bytes'")
                continuation.yield(buffer)
                buffer = Data()
                reportDate = Date()
            }
        }
    }
    
    // 3. CRITICAL: Tells the stream when the operation is completely finished or errored out
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Log4swift[Self.self].error("error: '\(error)'")
            Log4swift[Self.self].error("downloadURL: '\(downloadURL.absoluteString)'")
            continuation.finish()
        } else {
            lock.withLock {
                continuation.yield(buffer)
                buffer = Data()
            }
            continuation.finish()
        }
    }
}

internal struct MacOS11Download {
    func downloadUpdate(_ downloadURL: URL) -> AsyncStream<Data> {
        AsyncStream<Data> { continuation in
            let request = URLRequest(url: downloadURL)
            let delegate = MacOS11DownloadDelegate(
                downloadURL: downloadURL,
                continuation: continuation
            )
            let configuration = URLSessionConfiguration.default
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

            let task = session.dataTask(with: request)

            // Clean up the session when the stream is terminated by the consumer
            continuation.onTermination = { _ in
                task.cancel()
                session.invalidateAndCancel()
            }

            task.resume()
        }
    }
}
