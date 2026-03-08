//
//  MainContentCoordinator+MongoDB.swift
//  TablePro
//
//  MongoDB-specific query helpers for MainContentCoordinator.
//

import Foundation
import TableProPluginKit

extension MainContentCoordinator {
    /// Converts a MQL query into a `db.runCommand({"explain": ...})` command.
    /// For find operations, builds a structured explain with filter and options.
    /// For other operations, returns a generic runCommand explain wrapper.
    static func buildMongoExplain(for query: String) -> String {
        guard let operation = try? MongoShellParser.parse(query) else {
            return "db.runCommand({\"explain\": \"\(query)\", \"verbosity\": \"executionStats\"})"
        }

        switch operation {
        case .find(let collection, let filter, let options):
            var findDoc = "\"find\": \"\(collection)\", \"filter\": \(filter)"
            if let sort = options.sort {
                findDoc += ", \"sort\": \(sort)"
            }
            if let skip = options.skip {
                findDoc += ", \"skip\": \(skip)"
            }
            if let limit = options.limit {
                findDoc += ", \"limit\": \(limit)"
            }
            if let projection = options.projection {
                findDoc += ", \"projection\": \(projection)"
            }
            return "db.runCommand({\"explain\": {\(findDoc)}, \"verbosity\": \"executionStats\"})"

        case .findOne(let collection, let filter):
            return "db.runCommand({\"explain\": {\"find\": \"\(collection)\", \"filter\": \(filter), \"limit\": 1}, \"verbosity\": \"executionStats\"})"

        case .aggregate(let collection, let pipeline):
            return "db.runCommand({\"explain\": {\"aggregate\": \"\(collection)\", \"pipeline\": \(pipeline), \"cursor\": {}}, \"verbosity\": \"executionStats\"})"

        case .countDocuments(let collection, let filter):
            return "db.runCommand({\"explain\": {\"count\": \"\(collection)\", \"query\": \(filter)}, \"verbosity\": \"executionStats\"})"

        case .deleteOne(let collection, let filter):
            return "db.runCommand({\"explain\": {\"delete\": \"\(collection)\", \"deletes\": [{\"q\": \(filter), \"limit\": 1}]}, \"verbosity\": \"executionStats\"})"

        case .deleteMany(let collection, let filter):
            return "db.runCommand({\"explain\": {\"delete\": \"\(collection)\", \"deletes\": [{\"q\": \(filter), \"limit\": 0}]}, \"verbosity\": \"executionStats\"})"

        case .updateOne(let collection, let filter, let update):
            return "db.runCommand({\"explain\": {\"update\": \"\(collection)\", \"updates\": [{\"q\": \(filter), \"u\": \(update), \"multi\": false}]}, \"verbosity\": \"executionStats\"})"

        case .updateMany(let collection, let filter, let update):
            return "db.runCommand({\"explain\": {\"update\": \"\(collection)\", \"updates\": [{\"q\": \(filter), \"u\": \(update), \"multi\": true}]}, \"verbosity\": \"executionStats\"})"

        case .findOneAndUpdate(let collection, let filter, let update):
            let cmd = "\"findAndModify\": \"\(collection)\", \"query\": \(filter), \"update\": \(update)"
            return "db.runCommand({\"explain\": {\(cmd)}, \"verbosity\": \"executionStats\"})"

        case .findOneAndReplace(let collection, let filter, let replacement):
            let cmd = "\"findAndModify\": \"\(collection)\", \"query\": \(filter), \"update\": \(replacement)"
            return "db.runCommand({\"explain\": {\(cmd)}, \"verbosity\": \"executionStats\"})"

        case .findOneAndDelete(let collection, let filter):
            let cmd = "\"findAndModify\": \"\(collection)\", \"query\": \(filter), \"remove\": true"
            return "db.runCommand({\"explain\": {\(cmd)}, \"verbosity\": \"executionStats\"})"

        default:
            return "db.runCommand({\"explain\": \"\(query)\", \"verbosity\": \"executionStats\"})"
        }
    }
}
