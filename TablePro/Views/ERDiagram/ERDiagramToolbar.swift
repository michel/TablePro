import SwiftUI

struct ERDiagramToolbar: View {
    @Bindable var viewModel: ERDiagramViewModel
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.magnification = max(0.25, viewModel.magnification - 0.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)

            Text("\(Int(viewModel.magnification * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 40)
                .foregroundStyle(.secondary)

            Button {
                viewModel.magnification = min(3.0, viewModel.magnification + 0.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)

            Divider().frame(height: 16)

            Toggle(isOn: $viewModel.isCompactMode) {
                Image(systemName: "rectangle.compress.vertical")
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .help(String(localized: "Compact Mode"))

            Divider().frame(height: 16)

            Button {
                viewModel.resetLayout()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Reset Layout"))

            Button(action: onExport) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Export as PNG"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .padding(12)
    }
}
