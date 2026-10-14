import SwiftUI
import UIKit

enum PlayerTheme: String, CaseIterable, Identifiable {
    case artwork, midnight, paper
    var id: String { rawValue }
    var name: String {
        switch self {
        case .artwork: return "ジャケットに合わせる"
        case .midnight: return "ミッドナイト"
        case .paper: return "ペーパー"
        }
    }
}

struct PlayerPalette {
    let top: Color
    let bottom: Color
    let text: Color
    let secondary: Color
    let accent: Color

    init(theme: PlayerTheme, tint: UIColor) {
        switch theme {
        case .artwork:
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            tint.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            let saturation = s < 0.08 ? s : min(0.85, max(0.38, s))
            top = Color(UIColor(hue: h, saturation: saturation, brightness: min(0.68, max(0.42, b * 0.8)), alpha: 1))
            bottom = Color(UIColor(hue: h, saturation: min(1, saturation * 1.15), brightness: min(0.3, max(0.12, b * 0.32)), alpha: 1))
            text = .white; secondary = .white.opacity(0.62); accent = .white
        case .midnight:
            top = Color(red: 0.12, green: 0.13, blue: 0.20)
            bottom = Color(red: 0.035, green: 0.04, blue: 0.065)
            text = .white; secondary = .white.opacity(0.6)
            accent = Color(red: 0.75, green: 0.77, blue: 1)
        case .paper:
            top = Color(red: 0.97, green: 0.95, blue: 0.91)
            bottom = Color(red: 0.91, green: 0.89, blue: 0.85)
            text = Color(red: 0.18, green: 0.16, blue: 0.15)
            secondary = text.opacity(0.6)
            accent = Color(red: 0.5, green: 0.3, blue: 0.22)
        }
    }
}

struct CoverView: View {
    let image: UIImage?
    var cornerRadius: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(Color.black.opacity(0.12))
                } else {
                    LinearGradient(colors: [Color(red: 0.46, green: 0.38, blue: 0.62),
                                            Color(red: 0.20, green: 0.23, blue: 0.38)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().stroke(.white.opacity(0.12), lineWidth: geometry.size.width * 0.08)
                        .padding(geometry.size.width * 0.17)
                    Image(systemName: "music.note").font(.system(size: max(16, geometry.size.width * 0.25), weight: .light))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }.aspectRatio(1, contentMode: .fit)
    }
}

extension UIImage {
    var prominentColor: UIColor? {
        guard let cgImage else { return averageColor }
        let size = 20
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let succeeded = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                          bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size)); return true
        }
        guard succeeded else { return averageColor }
        var weights = [CGFloat](repeating: 0, count: 12)
        var colors = [UIColor?](repeating: nil, count: 12)
        var best = [CGFloat](repeating: 0, count: 12)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let color = UIColor(red: CGFloat(pixels[index]) / 255, green: CGFloat(pixels[index + 1]) / 255,
                                blue: CGFloat(pixels[index + 2]) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            guard s > 0.12, b > 0.2, pixels[index + 3] > 200 else { continue }
            let bucket = min(11, Int(h * 12)), score = s * b
            weights[bucket] += score
            if score > best[bucket] { best[bucket] = score; colors[bucket] = color }
        }
        guard let bucket = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[bucket] > 0 else { return averageColor }
        return colors[bucket]
    }

    var averageColor: UIColor? {
        guard let cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let succeeded = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard succeeded else { return nil }
        return UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                       blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }
}
