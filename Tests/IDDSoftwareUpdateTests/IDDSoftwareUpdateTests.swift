import XCTest
import Log4swift
import Logging
import IDDSwift
// @testable import IDDSwiftTests

final class IDDSoftwareUpdateTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
//        XCTAssertEqual(IDDCommons().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
    
    override func setUp() async throws {
        LoggingSystem.bootstrap { label in
            ConsoleHandler(label: label)
        }
    }
    
    /**
     Create the file where the asyncOutput will go
     touch /tmp/asyncOutput.log
     you can tail it
     tail -f /tmp/asyncOutput.log

     Create the test file
     touch /tmp/test.log
     append to it
     echo "`date` 123 this is cool" >> /tmp/test.log^C
     echo "`date +"%Y-%m-%d %H:%M:%S"` magical shrums" >> /tmp/test.log
     echo "`date +"%Y-%m-%d %H:%M:%S"` magical shrums `uuidgen`" >> /tmp/test.log
     */
    func testAsyncOutput() async {
        let logFile = URL(fileURLWithPath: "/tmp/asyncOutput.log")
        let process = Process(URL(fileURLWithPath: "/usr/bin/tail"), [
            "-f",
            "/tmp/test.log"
        ])
        // let process = Process(URL(fileURLWithPath: "/usr/bin/grep"), [
        //     "Magical Shrums",
        //     "/tmp/test.log"
        // ])
        
        Log4swift[Self.self].info("-----")
        Log4swift[Self.self].info("Starting ...")
        guard let fileHandle = try? FileHandle(forWritingTo: logFile)
        else {
            // make sure the file is there and available for writing
            XCTFail("Failed to create write handle on: '\(logFile.path)'", file: #file, line: #line)
            return
        }
        
        for await output in process.asyncOutput(timeOut: 60) {
            switch output {
            case let .error(error):
                Log4swift[Self.self].error("output: \(error)")
                
            case let .terminated(reason):
                Log4swift[Self.self].info("-----")
                switch reason {
                case .exit:
                    Log4swift[Self.self].info("terminated: 'exit \(reason.rawValue)' usually a normal process termination")
                case .uncaughtSignal:
                    Log4swift[Self.self].info("terminated: 'uncaughtSignal \(reason.rawValue)' most likely the process got killed")
                @unknown default:
                    Log4swift[Self.self].info("terminated: 'unknown \(reason.rawValue)'")
                }
                Log4swift[Self.self].info("-----")

            case let .stdout(data):
                try? fileHandle.write(contentsOf: data)
                
                let message = String(data: data, encoding: .utf8) ?? ""
                fputs(message, stdout)
                
            case let .stderr(data):
                try? fileHandle.write(contentsOf: data)

                let message = String(data: data, encoding: .utf8) ?? ""
                fputs(message, stdout)
            }
        }
        Log4swift[Self.self].info("Terminated")
        Log4swift[Self.self].info("-----")
    }

    /**
     Create a shell script
     touch /tmp/tmutil
     chmod +x /tmp/tmutil
     with these contents
     #!/bin/sh
     #
     #

     echo "Test 123, Test 123, Test 123"
     sleep 4
     exit 0
     */
    func testProcessFetchString() async {
        // we want to log
        UserDefaults.standard.setValue("D", forKey: "IDDSwift.Process")

        let tmutilURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        // let tmutilURL = URL(fileURLWithPath: "/tmp/tmutil")

        //  /usr/bin/tmutil listbackups
        //  /usr/bin/tmutil machinedirectory
        //  /usr/bin/tmutil destinationinfo -X
        //  /usr/bin/tmutil uniquesize /Volumes/Vault/Backups.backupdb/macpro3000/2015-06-09-113054/Yosemite\ XP941/Users/kdeda/

        do {
            let processData = try Process.processData(taskURL: tmutilURL, arguments: ["machinedirectory"], timeOut: 3.0)

            Log4swift[Self.self].info("processData.stdout: '\(processData.stdOutString)'")
            Log4swift[Self.self].info("processData.stderr: '\(processData.stdErrorString)'")
        } catch {
            Log4swift[Self.self].info("processError.error: '\(error)'")
        }

        XCTAssert(true, "Failed to create write handle on")
        Log4swift[Self.self].info("Completed")
        Log4swift[Self.self].info("-----")
    }

    func testSH256() async {
        let url = URL(fileURLWithPath: "/Users/kdeda/Desktop/Packages/WhatSize_8.0.8/WhatSize.tgz")
        let sha256 = url.sha256

        XCTAssertEqual(sha256, "DADF281E1F4141B5-5A23014632-9522057CE976-F3F5B9D2D369-68B0AF513EC086")
        Log4swift[Self.self].info("Completed")
        Log4swift[Self.self].info("-----")
    }

}
