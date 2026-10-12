import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var server: LocalHTTPServer

    @State private var selectedCategoryID: String?
    @State private var selectedAction: ActionItem?

    private var selectedCategory: ActionCategory? {
        let categoryID = selectedCategoryID ?? library.categories.first?.id
        return library.categories.first { $0.id == categoryID }
    }

    private var requestedActionID: Int? {
        if let value = ProcessInfo.processInfo.environment["BODY3D_ACTION_ID"],
           let id = Int(value) {
            return id
        }

        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--body3d-action-id"),
              arguments.indices.contains(flag + 1) else {
            return nil
        }
        return Int(arguments[flag + 1])
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedCategoryID) {
                ForEach(library.categories) { category in
                    HStack(spacing: 8) {
                        Text(category.nameCN)
                            .font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Text("\(category.items.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    .tag(category.id)
                }
            }
            .navigationTitle("关节-肌群解析")
            .listStyle(.sidebar)
        } detail: {
            Group {
                if let action = selectedAction {
                    ViewerPage(action: action) {
                        selectedAction = nil
                    }
                } else if let category = selectedCategory {
                    ActionGrid(category: category) { action in
                        selectedAction = action
                    }
                } else if let error = library.errorMessage {
                    ContentUnavailableView(
                        "无法载入模型",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    ProgressView("读取离线模型…")
                }
            }
        }
        .onChange(of: selectedCategoryID) { _, categoryID in
            if selectedAction?.nounsCN != categoryID {
                selectedAction = nil
            }
        }
        .onChange(of: library.categories) { _, categories in
            if let requestedActionID,
               let category = categories.first(where: { category in
                   category.items.contains(where: { $0.id == requestedActionID })
               }),
               let action = category.items.first(where: { $0.id == requestedActionID }) {
                selectedAction = action
                selectedCategoryID = category.id
            } else if selectedCategoryID == nil {
                selectedCategoryID = categories.first?.id
            }
        }
        .task(id: library.categories) {
            guard let requestedActionID,
                  let category = library.categories.first(where: { category in
                      category.items.contains(where: { $0.id == requestedActionID })
                  }),
                  let action = category.items.first(where: { $0.id == requestedActionID }) else {
                return
            }
            selectedAction = action
            selectedCategoryID = category.id
        }
    }
}

private struct ActionGrid: View {
    @EnvironmentObject private var library: ModelLibrary
    let category: ActionCategory
    let onSelect: (ActionItem) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 230, maximum: 330), spacing: 18)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(category.items) { action in
                    Button {
                        onSelect(action)
                    } label: {
                        ActionCard(action: action, image: library.thumbnail(for: action))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(22)
        }
        .navigationTitle("\(category.nameCN)（\(category.items.count)）")
        .background(catalogBackground)
    }

    private var catalogBackground: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(uiColor: .systemBackground)
#endif
    }
}

private struct ActionCard: View {
    let action: ActionItem
    let image: PlatformImage?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.white
                if let image {
#if os(macOS)
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
#else
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
#endif
                } else {
                    Image(systemName: "figure.arms.open")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 210)

            VStack(spacing: 4) {
                Text(action.nameCN)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(action.nameEN)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .padding(.horizontal, 10)
            .background(cardFooterBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 7, y: 3)
    }


    private var cardFooterBackground: Color {
#if os(macOS)
        Color(nsColor: .darkGray)
#else
        Color(uiColor: .darkGray)
#endif
    }
}

private struct ViewerPage: View {
    @EnvironmentObject private var server: LocalHTTPServer
    let action: ActionItem
    let onBack: () -> Void

    private var viewerURL: URL? {
        guard let baseURL = server.baseURL else { return nil }
        return URL(string: "\(baseURL.absoluteString)#/action/\(action.id)")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Label("返回", systemImage: "chevron.left")
                }
#if os(macOS)
                .keyboardShortcut(.cancelAction)
#endif

                Divider().frame(height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.nameCN)
                        .font(.headline)
                    Text(action.nameEN)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("拖动旋转 · 滚轮缩放 · 右键拖动平移 · 双击聚焦")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(.bar)

            Divider()

            if let viewerURL {
                ModelWebView(url: viewerURL)
            } else if let error = server.errorMessage {
                ContentUnavailableView(
                    "离线服务启动失败",
                    systemImage: "network.slash",
                    description: Text(error)
                )
            } else {
                ProgressView("启动离线模型服务…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
