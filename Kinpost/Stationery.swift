import KinpostCore
import SwiftUI

extension ShapeStyle where Self == Color {
  static var postBlue: Color {
    Color(
      uiColor: UIColor {
        $0.userInterfaceStyle == .dark
          ? UIColor(red: 0.51, green: 0.66, blue: 1, alpha: 1)
          : UIColor(red: 0.12, green: 0.27, blue: 0.69, alpha: 1)
      })
  }
  static var paper: Color {
    Color(
      uiColor: UIColor {
        $0.userInterfaceStyle == .dark
          ? .systemGroupedBackground : UIColor(red: 0.973, green: 0.969, blue: 0.953, alpha: 1)
      })
  }
  static var pageRow: Color { Color(uiColor: .secondarySystemGroupedBackground) }
}
extension Audience {
  var symbol: String {
    switch self {
    case .phone: "phone"
    case .home: "house"
    case .personal: "person.crop.circle"
    case .household: "person.2"
    }
  }
}
struct Kicker: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text.uppercased()).font(.system(.caption2, design: .monospaced, weight: .semibold))
      .tracking(1.6)
  }
}
struct Stamp: View {
  var body: some View {
    ZStack {
      Canvas { context, size in
        let bounds = CGRect(origin: .zero, size: size)
        context.fill(Path(bounds), with: .color(.init(red: 0.88, green: 0.92, blue: 1)))
        context.blendMode = .destinationOut
        for y in stride(from: 3.0, to: size.height, by: 7) {
          for x in [0.0, size.width] {
            context.fill(
              Path(ellipseIn: CGRect(x: x - 2.4, y: y - 2.4, width: 4.8, height: 4.8)),
              with: .color(.black))
          }
        }
        for x in stride(from: 3.0, to: size.width, by: 7) {
          for y in [0.0, size.height] {
            context.fill(
              Path(ellipseIn: CGRect(x: x - 2.4, y: y - 2.4, width: 4.8, height: 4.8)),
              with: .color(.black))
          }
        }
      }
      VStack(spacing: 2) {
        Image(systemName: "paperplane.fill").font(.system(size: 25))
        Text("POST").font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(2)
      }
      .foregroundStyle(Color(red: 0.16, green: 0.30, blue: 0.64)).frame(
        maxWidth: .infinity, maxHeight: .infinity
      ).overlay(Rectangle().strokeBorder(Color.blue.opacity(0.45))).padding(6)
    }.frame(width: 48, height: 59).rotationEffect(.degrees(7)).accessibilityHidden(true)
  }
}
struct CallingCard: View {
  var card: Card
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top) {
        Label {
          Kicker("Kinpost")
        } icon: {
          Image(systemName: "rectangle.on.rectangle.angled")
        }
        Spacer()
        Stamp()
      }
      Spacer(minLength: 15)
      Text(card.name.isEmpty ? "Your name here" : card.name).font(
        .system(.largeTitle, design: .serif, weight: .medium)
      ).lineLimit(2).minimumScaleFactor(0.75)
      HStack(spacing: 5) {
        Image(systemName: "mappin")
        Text(
          [card.city, card.region].filter { !$0.isEmpty }.joined(separator: ", ").nonempty
            ?? "Personal contact card")
      }.font(.subheadline).foregroundStyle(.white.opacity(0.86)).padding(.top, 5)
      Rectangle().fill(.white.opacity(0.30)).frame(height: 1).padding(.vertical, 13)
      HStack {
        Kicker("Contact card")
        Spacer()
        Kicker("Owner’s copy")
      }.foregroundStyle(.white.opacity(0.85))
    }.padding(21).frame(maxWidth: .infinity, minHeight: 208, alignment: .leading).foregroundStyle(
      .white
    )
    .background {
      ZStack {
        LinearGradient(
          colors: [
            Color(red: 0.10, green: 0.22, blue: 0.53), Color(red: 0.19, green: 0.38, blue: 0.73),
          ], startPoint: .bottomLeading, endPoint: .topTrailing)
        Canvas { ctx, size in
          for i in 0..<37 {
            var p = Path()
            let off = CGFloat(i) * 4.8
            p.move(to: CGPoint(x: size.width * 0.29 + off, y: -20))
            p.addCurve(
              to: CGPoint(x: size.width + 35, y: size.height * 0.90 - off * 0.34),
              control1: CGPoint(x: size.width * 0.67 + off * 0.8, y: 45),
              control2: CGPoint(x: size.width * 0.48 + off * 0.5, y: size.height * 0.76))
            ctx.stroke(p, with: .color(.white.opacity(0.115)), lineWidth: 0.75)
          }
        }.accessibilityHidden(true)
      }
    }.clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityElement(children: .combine)
  }
}
extension String { var nonempty: String? { isEmpty ? nil : self } }
struct DetailLine: View {
  var icon: String, label: String, value: String
  var body: some View {
    HStack(spacing: 13) {
      Image(systemName: icon).font(.system(size: 17, weight: .medium)).foregroundStyle(.postBlue)
        .frame(width: 38, height: 38).background(
          .postBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
      VStack(alignment: .leading, spacing: 3) {
        Text(label).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.body).foregroundStyle(.primary)
      }
      Spacer(minLength: 2)
    }.padding(.vertical, 3).accessibilityElement(children: .combine)
  }
}
struct MainButton: View {
  var title: String, icon: String
  @Environment(\.colorScheme) private var colorScheme
  var body: some View {
    Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
      .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
  }
}
func displayDate(_ parts: DateComponents?) -> String? {
  guard let parts, let date = Calendar(identifier: .gregorian).date(from: parts) else { return nil }
  return date.formatted(date: .abbreviated, time: .omitted)
}
