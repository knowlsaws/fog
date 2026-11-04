import Foundation

/// 分潮の定義。天文引数 V = a·T + b·s + c·h + d·p + e·N + f·p' + 位相（Schureman の表記、T = 平均太陽の時角）。
/// 複合分潮（浅海分潮など）は基本分潮の整数結合で表し、V は和、ノード因子 f は積、u は和にする。
struct ConstituentDefinition {
    enum Nodal {
        case none, m2, k1, o1, k2, j1, oo1, mf, mm, m1, l2, m3
    }
    enum Kind {
        /// 係数 (T, s, h, p, N, p') と位相（度）
        case basic(coefficients: [Double], phase: Double, nodal: Nodal)
        /// 基本分潮の結合（名前と倍率）
        case compound([(String, Int)])
    }
    let name: String
    let kind: Kind
}

enum ConstituentTable {
    /// 名前のゆらぎ（気象庁の表記、ギリシャ文字、英字）を正規化する。
    static func canonicalName(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "")
        let map: [String: String] = [
            "SIG1": "σ1", "SIGMA1": "σ1", "sigma1": "σ1", "σ1": "σ1",
            "RHO1": "ρ1", "rho1": "ρ1", "ρ1": "ρ1",
            "PI1": "π1", "pi1": "π1", "π1": "π1",
            "PSI1": "ψ1", "psi1": "ψ1", "ψ1": "ψ1",
            "PHI1": "φ1", "phi1": "φ1", "φ1": "φ1", "FI1": "φ1",
            "THE1": "θ1", "THETA1": "θ1", "theta1": "θ1", "θ1": "θ1",
            "CHI1": "χ1", "chi1": "χ1", "χ1": "χ1",
            "LAM2": "λ2", "LAMBDA2": "λ2", "lambda2": "λ2", "λ2": "λ2",
            "MU2": "μ2", "mu2": "μ2", "μ2": "μ2", "2MS2": "μ2",
            "NU2": "ν2", "nu2": "ν2", "ν2": "ν2",
            "SA": "Sa", "SSA": "Ssa", "MM": "Mm", "MSF": "MSf", "MF": "Mf",
            "OO1": "OO1", "MSK6": "MSK6",
        ]
        if let m = map[s] { return m }
        if let m = map[s.uppercased()] { return m }
        return s
    }

    static let definitions: [String: ConstituentDefinition] = {
        var d: [ConstituentDefinition] = []
        func basic(_ n: String, _ c: [Double], _ ph: Double, _ nodal: ConstituentDefinition.Nodal) {
            d.append(ConstituentDefinition(name: n, kind: .basic(coefficients: c, phase: ph, nodal: nodal)))
        }
        func compound(_ n: String, _ parts: [(String, Int)]) {
            d.append(ConstituentDefinition(name: n, kind: .compound(parts)))
        }
        //                 T   s   h   p   N   p'
        basic("Sa",      [0,  0,  1,  0,  0,  0],   0, .none)
        basic("Ssa",     [0,  0,  2,  0,  0,  0],   0, .none)
        basic("Mm",      [0,  1,  0, -1,  0,  0],   0, .mm)
        basic("MSf",     [0,  2, -2,  0,  0,  0],   0, .m2)
        basic("Mf",      [0,  2,  0,  0,  0,  0],   0, .mf)
        basic("2Q1",     [1, -4,  1,  2,  0,  0],  90, .o1)
        basic("σ1",      [1, -4,  3,  0,  0,  0],  90, .o1)
        basic("Q1",      [1, -3,  1,  1,  0,  0],  90, .o1)
        basic("ρ1",      [1, -3,  3, -1,  0,  0],  90, .o1)
        basic("O1",      [1, -2,  1,  0,  0,  0],  90, .o1)
        basic("M1",      [1, -1,  1,  0,  0,  0], -90, .m1)   // 気象庁の M1（T − s + h、速度 14.4920521）
        basic("χ1",      [1, -1,  3, -1,  0,  0], -90, .j1)
        basic("π1",      [1,  0, -2,  0,  0,  1],  90, .none)
        basic("P1",      [1,  0, -1,  0,  0,  0],  90, .none)
        basic("S1",      [1,  0,  0,  0,  0,  0],   0, .none)
        basic("K1",      [1,  0,  1,  0,  0,  0], -90, .k1)
        basic("ψ1",      [1,  0,  2,  0,  0, -1], -90, .none)
        basic("φ1",      [1,  0,  3,  0,  0,  0], -90, .none)
        basic("θ1",      [1,  1, -1,  1,  0,  0], -90, .j1)
        basic("J1",      [1,  1,  1, -1,  0,  0], -90, .j1)
        basic("OO1",     [1,  2,  1,  0,  0,  0], -90, .oo1)
        basic("2N2",     [2, -4,  2,  2,  0,  0],   0, .m2)
        basic("μ2",      [2, -4,  4,  0,  0,  0],   0, .m2)
        basic("N2",      [2, -3,  2,  1,  0,  0],   0, .m2)
        basic("ν2",      [2, -3,  4, -1,  0,  0],   0, .m2)
        basic("M2",      [2, -2,  2,  0,  0,  0],   0, .m2)
        basic("λ2",      [2, -1,  0,  1,  0,  0], 180, .m2)
        basic("L2",      [2, -1,  2, -1,  0,  0], 180, .l2)
        basic("T2",      [2,  0, -1,  0,  0,  1],   0, .none)
        basic("S2",      [2,  0,  0,  0,  0,  0],   0, .none)
        basic("R2",      [2,  0,  1,  0,  0, -1], 180, .none)
        basic("K2",      [2,  0,  2,  0,  0,  0],   0, .k2)
        basic("M3",      [3, -3,  3,  0,  0,  0], 180, .m3)
        compound("MP1",  [("M2", 1), ("P1", -1)])
        compound("SO1",  [("S2", 1), ("O1", -1)])
        compound("OQ2",  [("O1", 1), ("Q1", 1)])
        compound("MNS2", [("M2", 1), ("N2", 1), ("S2", -1)])
        compound("OP2",  [("O1", 1), ("P1", 1)])
        compound("MKS2", [("M2", 1), ("K2", 1), ("S2", -1)])
        compound("MSN2", [("M2", 1), ("S2", 1), ("N2", -1)])
        compound("KJ2",  [("K1", 1), ("J1", 1)])
        compound("2SM2", [("S2", 2), ("M2", -1)])
        compound("MO3",  [("M2", 1), ("O1", 1)])
        compound("SO3",  [("S2", 1), ("O1", 1)])
        compound("MK3",  [("M2", 1), ("K1", 1)])
        compound("SK3",  [("S2", 1), ("K1", 1)])
        compound("MN4",  [("M2", 1), ("N2", 1)])
        compound("M4",   [("M2", 2)])
        compound("SN4",  [("S2", 1), ("N2", 1)])
        compound("MS4",  [("M2", 1), ("S2", 1)])
        compound("MK4",  [("M2", 1), ("K2", 1)])
        compound("S4",   [("S2", 2)])
        compound("SK4",  [("S2", 1), ("K2", 1)])
        compound("2MN6", [("M2", 2), ("N2", 1)])
        compound("M6",   [("M2", 3)])
        compound("MSN6", [("M2", 1), ("S2", 1), ("N2", 1)])
        compound("2MS6", [("M2", 2), ("S2", 1)])
        compound("2MK6", [("M2", 2), ("K2", 1)])
        compound("2SM6", [("S2", 2), ("M2", 1)])
        compound("MSK6", [("M2", 1), ("S2", 1), ("K2", 1)])
        compound("M8",   [("M2", 4)])
        compound("MS8",  [("M2", 3), ("S2", 1)])
        var dict: [String: ConstituentDefinition] = [:]
        for item in d { dict[item.name] = item }
        return dict
    }()

    /// 角速度（度/時）。テストと満干探索の刻み決めに使う。
    static let rates: [Double] = [15.0, 0.54901653, 0.04106864, 0.00464183, -0.00220641, 0.00000196]

    static func speedDegPerHour(_ name: String) -> Double? {
        guard let coeffs = coefficients(of: name) else { return nil }
        return zip(coeffs, rates).reduce(0) { $0 + $1.0 * $1.1 }
    }

    static func coefficients(of name: String) -> [Double]? {
        guard let def = definitions[canonicalName(name)] else { return nil }
        switch def.kind {
        case .basic(let c, _, _): return c
        case .compound(let parts):
            var sum = [Double](repeating: 0, count: 6)
            for (n, k) in parts {
                guard let c = coefficients(of: n) else { return nil }
                for i in 0..<6 { sum[i] += c[i] * Double(k) }
            }
            return sum
        }
    }
}
