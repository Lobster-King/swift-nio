//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CNIOLinux

#if os(Windows)
import let WinSDK.RelationProcessorCore

import func WinSDK.GetLastError
import func WinSDK.GetLogicalProcessorInformation

import struct WinSDK.SYSTEM_LOGICAL_PROCESSOR_INFORMATION

import typealias WinSDK.DWORD
#endif

/// A utility function that runs the body code only in debug builds, without
/// emitting compiler warnings.
///
/// This is currently the only way to do this in Swift: see
/// https://forums.swift.org/t/support-debug-only-code/11037 for a discussion.
@inlinable
internal func debugOnly(_ body: () -> Void) {
    assert({ body(); return true }())
}

/// Allows to "box" another value.
final class Box<T> {
    let value: T
    init(_ value: T) { self.value = value }
}

public enum System {
    /// A utility function that returns an estimate of the number of *logical* cores
    /// on the system.
    ///
    /// This value can be used to help provide an estimate of how many threads to use with
    /// the `MultiThreadedEventLoopGroup`. The exact ratio between this number and the number
    /// of threads to use is a matter for the programmer, and can be determined based on the
    /// specific execution behaviour of the program.
    ///
    /// - returns: The logical core count on the system.
    public static var coreCount: Int {
#if os(Windows)
        var dwLength: DWORD = 0
        _ = GetLogicalProcessorInformation(nil, &dwLength)

        let alignment: Int =
            MemoryLayout<SYSTEM_LOGICAL_PROCESSOR_INFORMATION>.alignment
        let pBuffer: UnsafeMutableRawPointer =
            UnsafeMutableRawPointer.allocate(byteCount: Int(dwLength),
                                             alignment: alignment)
        defer {
            pBuffer.deallocate()
        }

        let dwSLPICount: Int =
            Int(dwLength) / MemoryLayout<SYSTEM_LOGICAL_PROCESSOR_INFORMATION>.stride
        let pSLPI: UnsafeMutablePointer<SYSTEM_LOGICAL_PROCESSOR_INFORMATION> =
            pBuffer.bindMemory(to: SYSTEM_LOGICAL_PROCESSOR_INFORMATION.self,
                               capacity: dwSLPICount)

        let bResult: Bool = GetLogicalProcessorInformation(pSLPI, &dwLength)
        precondition(bResult, "GetLogicalProcessorInformation: \(GetLastError())")

        return UnsafeBufferPointer<SYSTEM_LOGICAL_PROCESSOR_INFORMATION>(start: pSLPI,
                                                                         count: dwSLPICount)
            .filter { $0.Relationship == RelationProcessorCore }
            .map { $0.ProcessorMask.nonzeroBitCount }
            .reduce(0, +)
#elseif os(Linux)
        if let quota = Linux.coreCount(quota: Linux.cfsQuotaPath, period: Linux.cfsPeriodPath) {
            return quota
        } else if let cpusetCount = Linux.coreCount(cpuset: Linux.cpuSetPath) {
            return cpusetCount
        } else {
            return sysconf(CInt(_SC_NPROCESSORS_ONLN))
        }
#else
        return sysconf(CInt(_SC_NPROCESSORS_ONLN))
#endif
    }

    /// A utility function that enumerates the available network interfaces on this machine.
    ///
    /// This function returns values that are true for a brief snapshot in time. These results can
    /// change, and the returned values will not change to reflect them. This function must be called
    /// again to get new results.
    ///
    /// - returns: An array of network interfaces available on this machine.
    /// - throws: If an error is encountered while enumerating interfaces.
    @available(*, deprecated, renamed: "enumerateDevices")
    public static func enumerateInterfaces() throws -> [NIONetworkInterface] {
        var interface: UnsafeMutablePointer<ifaddrs>? = nil
        try Posix.getifaddrs(&interface)
        let originalInterface = interface
        defer {
            freeifaddrs(originalInterface)
        }

        var results: [NIONetworkInterface] = []
        results.reserveCapacity(12)  // Arbitrary choice.
        while let concreteInterface = interface {
            if let nioInterface = NIONetworkInterface(concreteInterface.pointee) {
                results.append(nioInterface)
            }
            interface = concreteInterface.pointee.ifa_next
        }

        return results
    }

    /// A utility function that enumerates the available network devices on this machine.
    ///
    /// This function returns values that are true for a brief snapshot in time. These results can
    /// change, and the returned values will not change to reflect them. This function must be called
    /// again to get new results.
    ///
    /// - returns: An array of network devices available on this machine.
    /// - throws: If an error is encountered while enumerating interfaces.
    public static func enumerateDevices() throws -> [NIONetworkDevice] {
        var interface: UnsafeMutablePointer<ifaddrs>? = nil
        try Posix.getifaddrs(&interface)
        let originalInterface = interface
        defer {
            freeifaddrs(originalInterface)
        }

        var results: [NIONetworkDevice] = []
        results.reserveCapacity(12)  // Arbitrary choice.
        while let concreteInterface = interface {
            if let nioInterface = NIONetworkDevice(concreteInterface.pointee) {
                results.append(nioInterface)
            }
            interface = concreteInterface.pointee.ifa_next
        }

        return results
    }
}
