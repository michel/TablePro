//
//  DatabaseConnection+SSH.swift
//  TablePro
//

extension DatabaseConnection {
    /// Resolves the effective SSH configuration for this connection.
    /// When an SSH profile is referenced and provided, uses the profile's config.
    /// Otherwise falls back to the inline `sshConfig`.
    func effectiveSSHConfig(profile: SSHProfile?) -> SSHConfiguration {
        if sshProfileId != nil, let profile {
            return profile.toSSHConfiguration()
        }
        return sshConfig
    }
}
