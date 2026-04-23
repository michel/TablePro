//
//  DataGridSkeletonView.swift
//  TablePro
//
//  Loading placeholder for data grid and structure views.
//

import SwiftUI

struct DataGridSkeletonView: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
