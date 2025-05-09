//
//  SoftwareUpdateClient+Installation.swift
//  idd-softwareupdate
//
//  Created by Klajd Deda on 1/31/25.
//  Copyright (C) 1997-2025 id-design, inc. All rights reserved.
//

import Foundation
import IDDSwift
import Log4swift

fileprivate extension String {

    /**
     Creates the script we should run to perform the upgrade.
     This scripts operates on a proper .pkg
     1. pkgRoot         The folder that the .pkg has been downloaded earlier
     2. pkgName         The name of the .pkg, such as `WhatSize.pkg` inside the pkgRoot url from above
     3. unixShortName   The unix name of the user that initiated this entire flow
     4. applicationPath The path of the application we need to restart as `unixShortName` at the end of this script

     Copy the content of this into your choosen location to be run later
     */
    static func installUpgradeScript(pkgRoot: URL, pkgName: String, unixShortName: String, applicationPath: String) -> Self {
        let processName = Bundle.main.executableURL?.lastPathComponent ?? "unknown"
        let rv = """
        #!/bin/sh
        #
        # This is autogenerated by \(processName)
        # do not mock with it
        # Date: \(Date().stringWithDefaultFormat)
        #
        
        if [ $EUID -ne 0 ]; then
            echo "Running as user: \""${USER}"\""
            echo "You must execute these scripts as root/sudo."
            exit 1
        fi
        
        # will contain, the WhatSize.pkg, UpdateInfo.json and this shell script
        ROOT_PATH=\(pkgRoot.path)
        
        # When called this script will
        # 1. Install \(pkgName)
        #    The pkg has a preinstall and postinstall scripts
        #    1. preinstall will run before all and will kill WhatSize.app and remove older apps
        #    2. /usr/sbin/installer will deploy the files
        #    3. postinstall will run after the package and show the newly installed app in the Finder
        #
        # 2. Relaunch WhatSize.app in user space with -installUpgradeCompleted "${ROOT_PATH}"
        #    This will tell the app that we just got upgraded from this path
        
        echo ""
        echo "/usr/sbin/installer -dumplog -verbose -pkg "${ROOT_PATH}/\(pkgName)" -target /"
        /usr/sbin/installer -dumplog -verbose -pkg "${ROOT_PATH}/\(pkgName)" -target /
        echo "done"
        
        echo ""
        echo "/usr/bin/su - \(unixShortName) -c '/usr/bin/open "\(applicationPath)" --args -installUpgradeCompleted "\(pkgRoot.path)" &'"
        /usr/bin/su - \(unixShortName) -c '/usr/bin/open "\(applicationPath)" --args -installUpgradeCompleted "\(pkgRoot.path)" &'
        echo "done"
        
        exit 0
        
        """
        return rv
    }
}

extension SoftwareUpdateClient {
    // MARK: - UPGRADE STEP.1 -
    /**
     We shall be inside the context of the priviledged tool, it is important since we will copy ourselves in a temp folder in order to upgrade in place.

     1. pkgFilePath     The path to the new downloaded package. Usually inside a tmp folder, it will allow us the chance to run a script from there.
     2. unixShortName   The unix name of the user that initiated this entire flow
     3. applicationPath The path of the application we need to restart as `unixShortName` at the end of this script

     We will generate the installUpgrade.sh script
     We will copy this binary, (com.id-design.v8.whatsizehelper) into the package as well

     We have to since running the installUpgrade.sh will replace this executable
     so we will run it from the copy
     */
    public func prepareInstallUpgrade(
        _ pkgFilePath: String,
        _ unixShortName: String,
        _ applicationPath: String
    ) -> Bool {
        guard let executableURL = Bundle.main.executableURL
        else {
            Log4swift[Self.self].error("This should not happen")
            return false
        }

        let attributes: [FileAttributeKey : Any] = [
            .posixPermissions: NSNumber(value: 0o777),
            .creationDate: Date(),
            .modificationDate: Date()
        ]
        let pkgFileURL = URL(fileURLWithPath: pkgFilePath)
        let tempRoot = pkgFileURL.deletingLastPathComponent()
        let pkgName = pkgFileURL.lastPathComponent

        Log4swift[Self.self].dash("         tempRoot: '\(tempRoot.path)'")
        Log4swift[Self.self].info("         tempRoot: '\(tempRoot.path)'")
        Log4swift[Self.self].info("             step: 'UPGRADE STEP.1 / 3'")
        Log4swift[Self.self].info("          pkgName: '\(pkgName)'")
        Log4swift[Self.self].info("  applicationPath: '\(applicationPath)'")

        // copy the installUpgrade.sh script in the temp
        let installUpgradeURL = tempRoot.appendingPathComponent("installUpgrade.sh")
        do {
            let installUpgradeScript = String.installUpgradeScript(pkgRoot: tempRoot, pkgName: pkgName, unixShortName: unixShortName, applicationPath: applicationPath)
            try installUpgradeScript.write(to: installUpgradeURL, atomically: true, encoding: .utf8)
            Log4swift[Self.self].info("          created: '\(installUpgradeURL.path)'")

            try FileManager.default.setAttributes(attributes, ofItemAtPath: installUpgradeURL.path)
            Log4swift[Self.self].info("  made executable: '\(installUpgradeURL.path)'")
        } catch {
            Log4swift[Self.self].error("error: '\(error)'")
            Log4swift[Self.self].error("failed to create: '\(installUpgradeURL.path)'")
            return false
        }

        // copy this executable binary in the temp
        let clonedHelperPathURL = tempRoot.appendingPathComponent(executableURL.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: executableURL, to: clonedHelperPathURL)
            Log4swift[Self.self].info(" clonedHelperPath: '\(clonedHelperPathURL.path)'")

            try FileManager.default.setAttributes(attributes, ofItemAtPath: clonedHelperPathURL.path)
            Log4swift[Self.self].info("  made executable: '\(clonedHelperPathURL.path)'")
        } catch {
            Log4swift[Self.self].error("error: '\(error)'")
            Log4swift[Self.self].error("failed to create: '\(clonedHelperPathURL.path)'")
            return false
        }

        Log4swift[Self.self].info("           status: 'installUpgrade.sh is ready'")
        return true
    }

    // MARK: - UPGRADE STEP.2 -
    /**
     We shall be inside the context of the priviledged tool and have completed UPGRADE STEP 1.

     1. pkgFilePath     The path to the new downloaded package. Usually inside a tmp folder, it shall have the `installUpgrade.sh` there.
     */
    public func forkInstallUpgrade(_ pkgFilePath: String) -> Bool {
        guard let executableURL = Bundle.main.executableURL
        else {
            Log4swift[Self.self].error("This should not happen")
            return false
        }

        let pkgFileURL = URL(fileURLWithPath: pkgFilePath)
        let tempRoot = pkgFileURL.deletingLastPathComponent()
        let installUpgradeURL = tempRoot.appendingPathComponent("installUpgrade.sh")
        let clonedHelperPathURL = tempRoot.appendingPathComponent(executableURL.lastPathComponent)

        Log4swift[Self.self].dash("         tempRoot: '\(tempRoot.path)'")
        Log4swift[Self.self].info("         tempRoot: '\(tempRoot.path)'")
        Log4swift[Self.self].info("             step: 'UPGRADE STEP.2 / 3'")
        Log4swift[Self.self].info("   installUpgrade: '\(installUpgradeURL.path)'")
        Log4swift[Self.self].info(" clonedHelperPath: '\(clonedHelperPathURL.path)'")

        Task {
            // TODO: kdeda, create an executable in this package
            // January 2025
            // We need to create an executable here to do this work and not force the
            //
            // We are going to run the cloned/forked copy of this executable from the temporary
            // path with the argument as the temporary path
            // This will assure it to be disconnected from our installed locations
            // in that binary intercept the -executeInstallUpgrade path to run the executeInstallUpgrade
            //
            try? await Task.sleep(for: .milliseconds(250))
            let process = Process(URL(fileURLWithPath: clonedHelperPathURL.path), ["-executeInstallUpgrade", tempRoot.path])

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                Log4swift[Self.self].error("error: '\(error)'")
            }
            Log4swift[Self.self].info("completed")
        }
        return true
    }

    // MARK: - UPGRADE STEP.3 -
    /**
     We shall be inside the context of the cloned priviledged tool and have completed UPGRADE STEP 1 and UPGRADE STEP 2.

     It should run the `installUpgrade.sh` we created on UPGRADE STEP 1
     `/var/folders/_0/bb5dz9995mn2yv4bvcmhxwzr0000gn/T/whatsize_update_8180/installUpgrade.sh`

     Error - the package path specified was invalid
     Usually means full disk acccess is broken
     */
    public func executeInstallUpgrade(pkgRootURL: URL) {
        let semaphore = DispatchSemaphore(value: 0)
        let scriptURL = pkgRootURL.appendingPathComponent("installUpgrade.sh")

        Log4swift[Self.self].dash("   scriptURL: '\(scriptURL.path)'")
        Log4swift[Self.self].info("   scriptURL: '\(scriptURL.path)'")
        Log4swift[Self.self].info("        step: 'UPGRADE STEP.3 / 3'")
        let logger = Log4swift[Self.self]

        Task {
            let process = Process(URL(fileURLWithPath: "/bin/sh"), [scriptURL.path])

            process.waitUntilExit()
            func message(_ data: Data) -> String {
                // formatting this is a bitch, since you might receive impartial lines
                // for now just regurgitate what we receive
                let message_ = String(data: data, encoding: .utf8) ?? ""
                return message_
            }

            // wait for a max of 5 minutes
            for await output in process.asyncOutput(timeOut: 300) {
                switch output {
                case let .error(error): logger.error("output: \(error)")
                case .terminated:       ()
                case let .stdout(data): Log4swift.log(message(data))
                case let .stderr(data): Log4swift.log(message(data))
                }
            }
            semaphore.signal()
        }

        semaphore.wait()
        Log4swift[Self.self].info("-----")
    }
}
