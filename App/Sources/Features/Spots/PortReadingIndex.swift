import Foundation
import CoreFoundation
import Core

/// 港名の「よみ」索引（F-50）。同梱の港データ（約 4,000 件）の名前を CFStringTokenizer のラテン文字転写でよみに直し、
/// ひらがな・カタカナ・ローマ字・漢字のどれで打っても 1 文字ごとに即座に絞り込めるようにする。通信なし。
@MainActor
final class PortReadingIndex {
    static let shared = PortReadingIndex()

    struct Entry: Sendable {
        let port: Port
        let name: String
        let reading: String
    }

    private(set) var entries: [Entry] = []
    private var buildTask: Task<Void, Never>?

    /// 初回だけバックグラウンドで作る（1 秒弱）。
    func prepare(catalog: PortCatalog) {
        guard entries.isEmpty, buildTask == nil, !catalog.isEmpty else { return }
        let ports = catalog.ports
        buildTask = Task.detached(priority: .userInitiated) {
            let built = ports.map { Entry(port: $0, name: $0.name, reading: PortReadingIndex.reading(of: $0.name)) }
            await MainActor.run { PortReadingIndex.shared.entries = built }
        }
    }

    /// 名前の部分一致（漢字）か、よみの部分一致（かな・ローマ字）。前方一致を先に、短い名前を先に
    func search(_ raw: String, limit: Int = 40) -> [Port] {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let kana = Self.hiragana(q)
        var hits: [(Entry, Int)] = []
        for e in entries {
            var score: Int?
            if e.name.hasPrefix(q) { score = 0 }
            else if !kana.isEmpty, e.reading.hasPrefix(kana) { score = 1 }
            else if e.name.contains(q) { score = 2 }
            else if !kana.isEmpty, e.reading.contains(kana) { score = 3 }
            if let score { hits.append((e, score)) }
        }
        return hits.sorted { ($0.1, $0.0.name.count, $0.0.name) < ($1.1, $1.0.name.count, $1.0.name) }.prefix(limit).map { $0.0.port }
    }

    // MARK: 文字の変換

    /// 入力をひらがなに揃える：全角→半角、カタカナ→ひらがな、ローマ字→ひらがな、小文字
    nonisolated static func hiragana(_ s: String) -> String {
        let m = NSMutableString(string: s.lowercased())
        CFStringTransform(m, nil, kCFStringTransformFullwidthHalfwidth, false)
        CFStringTransform(m, nil, kCFStringTransformHiraganaKatakana, true)   // カタカナ → ひらがな
        CFStringTransform(m, nil, kCFStringTransformLatinHiragana, false)     // ローマ字 → ひらがな
        return (m as String).replacingOccurrences(of: " ", with: "")
    }

    /// 漢字まじりの名前のよみ（ひらがな）。ラテン文字転写 → ひらがな
    nonisolated static func reading(of s: String) -> String {
        let cf = s as CFString
        let tokenizer = CFStringTokenizerCreate(kCFAllocatorDefault, cf, CFRangeMake(0, CFStringGetLength(cf)), kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja_JP") as CFLocale)
        var latin = ""
        var type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while !type.isEmpty {
            if let t = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                latin += t
            }
            type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        let m = NSMutableString(string: latin.lowercased())
        CFStringTransform(m, nil, kCFStringTransformLatinHiragana, false)
        return (m as String).replacingOccurrences(of: " ", with: "")
    }

    /// 都道府県コード → 名前（表示用）
    static let prefectures: [String: String] = [
        "01": "北海道", "02": "青森県", "03": "岩手県", "04": "宮城県", "05": "秋田県", "06": "山形県", "07": "福島県", "08": "茨城県", "09": "栃木県", "10": "群馬県",
        "11": "埼玉県", "12": "千葉県", "13": "東京都", "14": "神奈川県", "15": "新潟県", "16": "富山県", "17": "石川県", "18": "福井県", "19": "山梨県", "20": "長野県",
        "21": "岐阜県", "22": "静岡県", "23": "愛知県", "24": "三重県", "25": "滋賀県", "26": "京都府", "27": "大阪府", "28": "兵庫県", "29": "奈良県", "30": "和歌山県",
        "31": "鳥取県", "32": "島根県", "33": "岡山県", "34": "広島県", "35": "山口県", "36": "徳島県", "37": "香川県", "38": "愛媛県", "39": "高知県", "40": "福岡県",
        "41": "佐賀県", "42": "長崎県", "43": "熊本県", "44": "大分県", "45": "宮崎県", "46": "鹿児島県", "47": "沖縄県",
    ]
}
