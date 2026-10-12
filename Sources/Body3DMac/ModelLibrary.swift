import Foundation
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

struct ActionItem: Codable, Identifiable, Hashable {
    let id: Int
    let nounsEN: String
    let nounsCN: String
    let nameEN: String
    let nameCN: String
    let actionGenre: Int
    let isFree: Bool?
}

struct ActionCategory: Identifiable, Hashable {
    var id: String { nameCN }
    let nameCN: String
    let nameEN: String
    let items: [ActionItem]
}

@MainActor
final class ModelLibrary: ObservableObject {
    @Published private(set) var categories: [ActionCategory] = []
    @Published private(set) var errorMessage: String?

    private let preferredOrder = [
        "头颈部", "面部", "肩部", "上肢",
        "躯干", "髋部和骨盆", "下肢", "粗大运动"
    ]

    var webRoot: URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let packaged = resourceURL.appendingPathComponent("Web", isDirectory: true)
            if FileManager.default.fileExists(atPath: packaged.path) {
                return packaged
            }
        }

        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/Body3DMac/Resources/Web", isDirectory: true)
        return FileManager.default.fileExists(atPath: development.path) ? development : nil
    }

    func load() {
        guard categories.isEmpty else { return }
        guard let root = webRoot else {
            errorMessage = "未找到离线资源目录。请先运行 Scripts/download_assets.py，再构建 App。"
            return
        }

        let metadataURL = root.appendingPathComponent("static/data/processed_data.json")
        do {
            let data = try Data(contentsOf: metadataURL)
            let items = try JSONDecoder().decode([ActionItem].self, from: data)
            let grouped = Dictionary(grouping: items, by: \ActionItem.nounsCN)
            categories = preferredOrder.compactMap { categoryName in
                guard let entries = grouped[categoryName], let first = entries.first else { return nil }
                return ActionCategory(
                    nameCN: categoryName,
                    nameEN: first.nounsEN,
                    items: entries
                )
            }
        } catch {
            errorMessage = "读取模型目录失败：\(error.localizedDescription)"
        }
    }

    func thumbnail(for item: ActionItem) -> PlatformImage? {
        guard let url = webRoot?.appendingPathComponent("thumbnails/\(item.id).jpg") else { return nil }
#if os(macOS)
        return NSImage(contentsOf: url)
#else
        return UIImage(contentsOfFile: url.path)
#endif
    }
}
