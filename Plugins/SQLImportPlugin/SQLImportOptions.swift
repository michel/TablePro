//
//  SQLImportOptions.swift
//  SQLImportPlugin
//

import Foundation

@Observable
final class SQLImportOptions {
    var wrapInTransaction: Bool = true
    var disableForeignKeyChecks: Bool = true
}
