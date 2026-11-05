import Foundation

/// 写真の背景から足場・時間帯・天気を推定する（F-31）。
/// App 側が Vision の画像分類ラベル（英語の識別子と信頼度）を渡し、ここで釣りの語彙に写す。通信なし。
public enum SceneTagger {
    public struct Tags: Hashable, Sendable {
        /// 岩場・テトラ・堤防・砂浜・船・磯・河口 など
        public var footing: String?
        /// 夜・朝夕・昼
        public var light: String?
        /// 晴れ・曇り・雨・雪
        public var sky: String?

        public var all: [String] { [footing, light, sky].compactMap { $0 } }
        public init(footing: String? = nil, light: String? = nil, sky: String? = nil) {
            self.footing = footing; self.light = light; self.sky = sky
        }
    }

    static let footingWords: [(String, [String])] = [
        ("テトラ", ["tetrapod", "breakwater", "concrete_block", "seawall"]),
        ("堤防", ["pier", "dock", "jetty", "wharf", "quay", "harbor", "port", "marina", "breakwater"]),
        ("岩場", ["rock", "cliff", "boulder", "reef", "stone"]),
        ("磯", ["shore", "coast", "coastline", "tide_pool"]),
        ("砂浜", ["beach", "sand", "dune"]),
        ("船", ["boat", "ship", "deck", "yacht", "kayak", "vessel"]),
        ("河口", ["river", "estuary", "creek", "stream"]),
        ("草地", ["grass", "field", "meadow"]),
    ]
    static let lightWords: [(String, [String])] = [
        ("夜", ["night", "dark", "moon", "flashlight", "lamp"]),
        ("朝夕", ["sunset", "sunrise", "dusk", "dawn", "twilight", "golden_hour"]),
    ]
    static let skyWords: [(String, [String])] = [
        ("雨", ["rain", "raindrop", "umbrella", "wet"]),
        ("雪", ["snow", "ice", "frost"]),
        ("曇り", ["cloud", "overcast", "fog", "mist", "haze"]),
        ("晴れ", ["sun", "sunny", "clear_sky", "blue_sky"]),
    ]

    /// `labels` は (識別子, 信頼度 0〜1)。`minConfidence` 未満は無視。
    public static func tags(from labels: [(String, Double)], minConfidence: Double = 0.2) -> Tags {
        // 識別子は "blue_sky" のように下線区切り。語の一部（"sunset" の "sun"）には反応しないよう、全体一致か語単位で比べる
        let usable: [(String, Set<String>, Double)] = labels.filter { $0.1 >= minConfidence }.map { l in
            let id = l.0.lowercased()
            return (id, Set(id.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == " " }).map(String.init)), l.1)
        }
        func pick(_ table: [(String, [String])]) -> String? {
            var best: (String, Double)?
            for (name, words) in table {
                let score = usable.filter { l in words.contains { l.0 == $0 || l.1.contains($0) } }.map { $0.2 }.max() ?? 0
                if score > 0, score > (best?.1 ?? 0) { best = (name, score) }
            }
            return best?.0
        }
        return Tags(footing: pick(footingWords), light: pick(lightWords), sky: pick(skyWords))
    }
}
