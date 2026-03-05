//
//  MainContentCoordinator+URLFilter.swift
//  TablePro
//

import Foundation

extension MainContentCoordinator {
    func setupURLNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .applyURLFilter,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let targetId = userInfo["connectionId"] as? UUID,
                  targetId == self.connectionId else { return }

            Task { @MainActor in
                self.applyURLFilter(userInfo: userInfo)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .switchSchemaFromURL,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let targetId = userInfo["connectionId"] as? UUID,
                  targetId == self.connectionId,
                  let schema = userInfo["schema"] as? String else { return }

            Task { @MainActor in
                if self.connection.type == .postgresql {
                    await self.switchSchema(to: schema)
                } else {
                    await self.switchDatabase(to: schema)
                }
            }
        }
    }

    private func applyURLFilter(userInfo: [AnyHashable: Any]) {
        if let condition = userInfo["condition"] as? String, !condition.isEmpty {
            let filter = TableFilter(
                id: UUID(),
                columnName: TableFilter.rawSQLColumn,
                filterOperator: .equal,
                value: "",
                isSelected: true,
                isEnabled: true,
                rawSQL: condition
            )
            filterStateManager.applySingleFilter(filter)
            return
        }

        guard let column = userInfo["column"] as? String, !column.isEmpty else { return }

        let operationString = userInfo["operation"] as? String ?? "Equal"
        let filterOp = mapTablePlusOperation(operationString)
        let value = userInfo["value"] as? String ?? ""

        let filter = TableFilter(
            id: UUID(),
            columnName: column,
            filterOperator: filterOp,
            value: value,
            isSelected: true,
            isEnabled: true
        )
        filterStateManager.applySingleFilter(filter)
    }

    private func mapTablePlusOperation(_ operation: String) -> FilterOperator {
        switch operation.lowercased() {
        case "equal", "equals", "=":
            return .equal
        case "not equal", "notequal", "!=":
            return .notEqual
        case "contains", "like":
            return .contains
        case "not contains", "notcontains", "not like":
            return .notContains
        case "starts with", "startswith":
            return .startsWith
        case "ends with", "endswith":
            return .endsWith
        case "greater than", "greaterthan", ">":
            return .greaterThan
        case "greater or equal", "greaterorequal", ">=":
            return .greaterOrEqual
        case "less than", "lessthan", "<":
            return .lessThan
        case "less or equal", "lessorequal", "<=":
            return .lessOrEqual
        case "is null", "isnull":
            return .isNull
        case "is not null", "isnotnull":
            return .isNotNull
        case "is empty", "isempty":
            return .isEmpty
        case "is not empty", "isnotempty":
            return .isNotEmpty
        case "in":
            return .inList
        case "not in", "notin":
            return .notInList
        case "between":
            return .between
        case "regex":
            return .regex
        default:
            return .contains
        }
    }
}
