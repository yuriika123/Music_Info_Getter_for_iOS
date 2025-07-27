import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyManager: HistoryManager

    var body: some View {
        NavigationView {
            if historyManager.history.isEmpty {
                Text("履歴はありません")
                    .foregroundColor(.secondary)
                    .navigationTitle("履歴")
            } else {
                List {
                    // 1. ForEachを使ってリストの各行を生成
                    ForEach(historyManager.history) { item in
                        HStack(spacing: 15) {
                            if let artwork = UIImage(data: item.artworkData) {
                                Image(uiImage: artwork)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(8)
                                    .shadow(radius: 3)
                            }
                            
                            VStack(alignment: .leading) {
                                Text(item.displayName)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(item.artistName)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                
                                // ★★★ 日時を表示する部分 ★★★
                                Text(formatDate(item.createdAt))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    // ★★★ スワイプ削除機能を追加する部分 ★★★
                    .onDelete(perform: deleteHistory)
                }
                .navigationTitle("履歴")
            }
        }
    }

    // MARK: - Helper Functions

    // 日付を「yyyy/MM/dd HH:mm」形式の文字列に変換する関数
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
    
    // 履歴を削除する関数
    private func deleteHistory(at offsets: IndexSet) {
        // どの行がスワイプされたかを受け取って、その行のデータを削除
        historyManager.history.remove(atOffsets: offsets)
        // 変更を永続的に保存するために、HistoryManagerのsaveHistoryを呼び出す
        // ※このためには、HistoryManagerのsaveHistoryをpublicにする必要がある
        historyManager.saveHistory()
    }
}
