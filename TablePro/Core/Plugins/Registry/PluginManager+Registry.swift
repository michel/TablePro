//
//  PluginManager+Registry.swift
//  TablePro
//

import CryptoKit
import Foundation
import os

extension PluginManager {
    func installFromRegistry(
        _ registryPlugin: RegistryPlugin,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> PluginEntry {
        if let minAppVersion = registryPlugin.minAppVersion {
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            if appVersion.compare(minAppVersion, options: .numeric) == .orderedAscending {
                throw PluginError.incompatibleWithCurrentApp(minimumRequired: minAppVersion)
            }
        }

        if let minKit = registryPlugin.minPluginKitVersion, minKit > Self.currentPluginKitVersion {
            throw PluginError.incompatibleVersion(required: minKit, current: Self.currentPluginKitVersion)
        }

        if plugins.contains(where: { $0.id == registryPlugin.id }) {
            throw PluginError.pluginConflict(existingName: registryPlugin.name)
        }

        guard let downloadURL = URL(string: registryPlugin.downloadURL) else {
            throw PluginError.downloadFailed("Invalid download URL")
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempZipURL = tempDir.appendingPathComponent("\(registryPlugin.id).zip")

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: downloadURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw PluginError.downloadFailed("HTTP \(statusCode)")
        }

        let expectedLength = httpResponse.expectedContentLength
        var downloadedData = Data()
        if expectedLength > 0 {
            downloadedData.reserveCapacity(Int(expectedLength))
        }

        var bytesReceived: Int64 = 0
        for try await byte in asyncBytes {
            downloadedData.append(byte)
            bytesReceived += 1

            if expectedLength > 0, bytesReceived % 65_536 == 0 {
                let fraction = Double(bytesReceived) / Double(expectedLength)
                await progress(min(fraction, 1.0))
            }
        }

        await progress(1.0)

        let digest = SHA256.hash(data: downloadedData)
        let hexChecksum = digest.map { String(format: "%02x", $0) }.joined()

        if hexChecksum != registryPlugin.sha256.lowercased() {
            throw PluginError.checksumMismatch
        }

        try downloadedData.write(to: tempZipURL)

        return try await installPlugin(from: tempZipURL)
    }
}
