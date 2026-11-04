import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// GPX（trkpt）の最小パーサ。位置シミュレーションのテストと、開発者が実機ログを読み込むのに使う。
public enum GPX {
    public static func parse(_ data: Data) -> [LocationFix] {
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.fixes
    }

    final class Delegate: NSObject, XMLParserDelegate {
        var fixes: [LocationFix] = []
        private var lat: Double?, lon: Double?, time: Date?, speed: Double?, hdop: Double?
        private var text = ""
        private let iso = ISO8601DateFormatter()

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if elementName == "trkpt" {
                lat = Double(attributeDict["lat"] ?? "")
                lon = Double(attributeDict["lon"] ?? "")
                time = nil; speed = nil; hdop = nil
            }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "time": time = iso.date(from: value) ?? FogJSON.parse(value)
            case "speed": speed = Double(value)
            case "hdop": hdop = Double(value)
            case "trkpt":
                if let lat, let lon, let time {
                    fixes.append(LocationFix(at: time, coordinate: Coordinate(latitude: lat, longitude: lon),
                                             horizontalAccuracyM: (hdop ?? 1) * 10, speedMS: speed))
                }
            default: break
            }
        }
    }
}
