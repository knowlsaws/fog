import SwiftUI
import MapKit
import Core

/// 地図の上に色面と粒子を描く（F-43）。地図の操作は通さない
struct MapLayersOverlay: View {
    let proxy: MapProxy
    let raster: FieldRaster?
    let particles: ParticleSystem
    let animate: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animate)) { timeline in
            Canvas(rendersAsynchronously: false) { ctx, _ in
                guard let raster,
                      let tl = proxy.convert(CLLocationCoordinate2D(latitude: raster.box.maxLat, longitude: raster.box.minLon), to: .local),
                      let br = proxy.convert(CLLocationCoordinate2D(latitude: raster.box.minLat, longitude: raster.box.maxLon), to: .local) else { return }
                let rect = CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
                if let img = raster.image {
                    ctx.draw(Image(decorative: img, scale: 1), in: rect)
                }
                if raster.layer.vector != nil, animate {
                    particles.step(raster: raster, now: timeline.date)
                    particles.draw(in: &ctx, rect: rect, layer: raster.layer)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 層のチップ・凡例・時刻バー
struct MapLayersControls: View {
    @Binding var layer: MapLayer
    @Binding var hourOffset: Int
    let start: Date
    let hours: Int
    let loading: Bool
    let error: String?
    private let tz = TimeZone(identifier: "Asia/Tokyo") ?? .current

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xs) {
                    ForEach(MapLayer.allCases) { l in
                        Button { layer = l } label: {
                            Text(l.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(layer == l ? DS.Color.background : DS.Color.textPrimary)
                                .padding(.horizontal, DS.Spacing.m).padding(.vertical, 6)
                                .background(layer == l ? DS.Color.accent : DS.Color.panel.opacity(0.9), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: DS.Spacing.s) {
                legend
                if loading { ProgressView().tint(DS.Color.textSecondary).scaleEffect(0.7) }
                if let error { Text(error).font(.system(size: 9)).foregroundStyle(DS.Color.textTertiary).lineLimit(1) }
                Spacer()
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            LinearGradient(stops: layer.stops.map { Gradient.Stop(color: Color(red: $0.1.0, green: $0.1.1, blue: $0.1.2), location: $0.0) }, startPoint: .leading, endPoint: .trailing)
                .frame(width: 90, height: 6).clipShape(Capsule())
            Text("\(layer.format(layer.range.lowerBound))〜\(layer.format(layer.range.upperBound)) \(layer.unit)").font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(DS.Color.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.s).padding(.vertical, 4)
        .background(DS.Color.panel.opacity(0.9), in: Capsule())
    }
}

/// 時刻バー：今から `hours` 時間先まで 1 時間刻み。タップとドラッグ
struct MapTimeBar: View {
    @Binding var hourOffset: Int
    let start: Date
    let hours: Int
    private let tz = TimeZone(identifier: "Asia/Tokyo") ?? .current

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frac = CGFloat(hourOffset) / CGFloat(max(1, hours))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(DS.Color.panel.opacity(0.95))
                // 日付の区切りと目盛り
                ForEach(0...(hours / 24), id: \.self) { d in
                    let x = w * CGFloat(d * 24) / CGFloat(max(1, hours))
                    Rectangle().fill(DS.Color.faded).frame(width: 1).offset(x: x)
                    Text(dayLabel(d)).font(.system(size: 9, weight: .semibold)).foregroundStyle(DS.Color.textTertiary).offset(x: x + 4, y: 2)
                }
                Capsule().fill(DS.Color.accent).frame(width: max(0, w * frac), height: 4).offset(y: geo.size.height - 10)
                Rectangle().fill(Color.white).frame(width: 2).offset(x: w * frac - 1)
                Text(label).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(DS.Color.textPrimary)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(DS.Color.background.opacity(0.85), in: Capsule())
                    .offset(x: min(max(0, w * frac - 28), w - 60), y: geo.size.height / 2 - 9)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                hourOffset = min(hours, max(0, Int((v.location.x / w * CGFloat(hours)).rounded())))
            })
        }
    }

    private var label: String {
        let d = start.addingTimeInterval(Double(hourOffset) * 3600)
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.timeZone = tz; f.dateFormat = "d日(E) H:00"
        return f.string(from: d)
    }

    private func dayLabel(_ d: Int) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.timeZone = tz; f.dateFormat = "d(E)"
        return f.string(from: start.addingTimeInterval(Double(d) * 86_400))
    }
}
