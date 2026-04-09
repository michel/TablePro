import Foundation

extension MainContentCoordinator {
    func openERDiagramTab() {
        let session = DatabaseManager.shared.session(for: connectionId)
        let dbName = session?.activeDatabase ?? connection.database
        let schemaName = session?.currentSchema
        let schemaKey = "\(dbName).\(schemaName ?? "default")"

        tabManager.addERDiagramTab(schemaKey: schemaKey, databaseName: dbName)
    }
}
