import Foundation

/// 潮汐の天文引数（度）。T は平均太陽の時角（0h UT で 180°）、s 月の平均黄経、h 太陽の平均黄経、
/// p 月の近地点黄経、N 月の昇交点黄経、p' 太陽の近地点黄経。
struct AstronomicalArguments {
    var T: Double
    var s: Double
    var h: Double
    var p: Double
    var N: Double
    var pp: Double

    /// `date`（UTC）で評価したグリニッジの引数。現地子午線基準の遅角には `TideEngine` が m·L を加える。
    init(at date: Date) {
        let jd = JulianDay.from(date)
        let t = JulianDay.centuries(jd)
        T = Angle.normalize(180 + 360 * JulianDay.fractionOfDay(jd))
        s = Angle.normalize(218.3164477 + 481267.88123421 * t - 0.0015786 * t * t + t * t * t / 538841)
        h = Angle.normalize(280.46646 + 36000.76983 * t + 0.0003032 * t * t)
        p = Angle.normalize(83.3532465 + 4069.0137287 * t - 0.0103200 * t * t - t * t * t / 80053)
        N = Angle.normalize(125.0445479 - 1934.1362891 * t + 0.0020754 * t * t + t * t * t / 467441)
        pp = Angle.normalize(282.93734 + 1.71946 * t + 0.00046 * t * t)
    }

    var vector: [Double] { [T, s, h, p, N, pp] }

    /// 分潮の平衡潮引数 V（度）とノード因子 f, u（度）。
    func argument(for name: String) -> (V: Double, f: Double, u: Double)? {
        guard let def = ConstituentTable.definitions[ConstituentTable.canonicalName(name)] else { return nil }
        switch def.kind {
        case .basic(let c, let phase, let nodal):
            let v = zip(c, vector).reduce(0) { $0 + $1.0 * $1.1 } + phase
            let (f, u) = nodalFactors(nodal)
            return (Angle.normalize(v), f, u)
        case .compound(let parts):
            var v = 0.0, f = 1.0, u = 0.0
            for (n, k) in parts {
                guard let a = argument(for: n) else { return nil }
                v += a.V * Double(k)
                f *= pow(a.f, Double(abs(k)))
                u += a.u * Double(k)
            }
            return (Angle.normalize(v), f, u)
        }
    }

    /// Schureman のノード因子（IHO の近似多項式）。
    func nodalFactors(_ kind: ConstituentDefinition.Nodal) -> (f: Double, u: Double) {
        let n = Angle.rad(N)
        let c1 = cos(n), c2 = cos(2 * n), c3 = cos(3 * n)
        let s1 = sin(n), s2 = sin(2 * n), s3 = sin(3 * n)
        switch kind {
        case .none:
            return (1, 0)
        case .m2:
            return (1.0004 - 0.0373 * c1 + 0.0002 * c2, -2.14 * s1)
        case .k1:
            return (1.0060 + 0.1150 * c1 - 0.0088 * c2 + 0.0006 * c3, -8.86 * s1 + 0.68 * s2 - 0.07 * s3)
        case .o1:
            return (1.0089 + 0.1871 * c1 - 0.0147 * c2 + 0.0014 * c3, 10.80 * s1 - 1.34 * s2 + 0.19 * s3)
        case .k2:
            return (1.0241 + 0.2863 * c1 + 0.0083 * c2 - 0.0015 * c3, -17.74 * s1 + 0.68 * s2 - 0.04 * s3)
        case .j1:
            return (1.0129 + 0.1676 * c1 - 0.0170 * c2 + 0.0016 * c3, -12.94 * s1 + 1.34 * s2 - 0.19 * s3)
        case .oo1:
            return (1.1027 + 0.6504 * c1 + 0.0317 * c2 - 0.0014 * c3, -36.68 * s1 + 4.02 * s2 - 0.57 * s3)
        case .mf:
            return (1.0429 + 0.4135 * c1 - 0.0040 * c2, -23.74 * s1 + 2.68 * s2 - 0.38 * s3)
        case .mm:
            return (1.0000 - 0.1300 * c1 + 0.0013 * c2, 0)
        case .m1:
            // M1 は近地点の位相で変わる複雑な因子。主要項だけ（Schureman 式 (207) の近似）
            let pr = Angle.rad(p)
            let f = sqrt(pow(2 * cos(pr) + 0.4 * cos(pr - n), 2) + pow(sin(pr) + 0.2 * sin(pr - n), 2))
            let u = Angle.deg(atan2(sin(pr) + 0.2 * sin(pr - n), 2 * cos(pr) + 0.4 * cos(pr - n)))
            return (f, u)
        case .l2:
            // L2 = M2 の因子 × (1/Ra)（Schureman 式 (214)）
            let (fm, um) = nodalFactors(.m2)
            let pr = Angle.rad(p)
            let x = 1 - 0.2505 * cos(2 * pr) - 0.1102 * cos(2 * pr - n) - 0.0156 * cos(2 * pr - 2 * n) - 0.037 * c1
            let y = -0.2505 * sin(2 * pr) - 0.1102 * sin(2 * pr - n) - 0.0156 * sin(2 * pr - 2 * n) - 0.037 * s1
            return (fm * sqrt(x * x + y * y), um + Angle.deg(atan2(y, x)))
        case .m3:
            let (fm, um) = nodalFactors(.m2)
            return (pow(fm, 1.5), 1.5 * um)
        }
    }
}
