import Foundation
import SwiftUI // UIImageのために必要

// ★★★ 1. 履歴データの型を定義 ★★★
struct HistoryItem: Identifiable, Codable {
    let id: UUID          // 履歴一つ一つを区別するためのID
    let musicItemID: String // 曲やアルバムのID（再取得用）
    let artworkData: Data   // アートワークの画像データ
    let displayName: String // 曲名やアルバム名
    let artistName: String  // アーティスト名
    let createdAt: Date     // 作成日時
}

// ★★★ 2. 履歴を管理するクラス ★★★
class HistoryManager: ObservableObject {
    @Published var history: [HistoryItem] = []
    private let historyKey = "music_history"

    init() {
        loadHistory()
    }

    // 履歴を追加する関数
    func addHistory(item: MusicItem, artwork: UIImage) {
        guard let artworkData = artwork.pngData() else { return }
        
        let newItem = HistoryItem(
            id: UUID(),
            musicItemID: item.id,
            artworkData: artworkData,
            displayName: item.displayName,
            artistName: item.artistName,
            createdAt: Date()
        )
        
        history.insert(newItem, at: 0)
        saveHistory()
    }

    // 履歴を端末に保存する関数
    func saveHistory() {
        if let encodedData = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encodedData, forKey: historyKey)
        }
    }

    // 端末から履歴を読み込む関数
    private func loadHistory() {
        if let savedData = UserDefaults.standard.data(forKey: historyKey) {
            if let decodedData = try? JSONDecoder().decode([HistoryItem].self, from: savedData) {
                history = decodedData
            }
        }
    }
}
