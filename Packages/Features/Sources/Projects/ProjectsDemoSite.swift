import CoreUI
import SwiftUI

/// What a made-up site says, by project name (the demo's four web projects each have their own; others get a plain one).
struct DemoSiteContent {
    let nav: [String]
    let action: String
    let headline: String
    let line: String
    let button: String
    let items: [String]
    let price: (Int) -> String

    static func of(_ name: String) -> DemoSiteContent {
        switch name {
        case "Northwind Ledger":
            return .init(
                nav: ["Product", "Pricing", "Docs"], action: "Sign in", headline: "Books that close themselves",
                line: "Invoices, ledgers and month-end in one calm place.", button: "Start a free trial",
                items: ["Invoices", "Ledger", "Payroll", "Reports"], price: { "$\(12 + $0 * 8) / mo" })
        case "Quill":
            return .init(
                nav: ["Features", "Templates", "Blog"], action: "Log in", headline: "Write it once. Publish it everywhere.",
                line: "A quiet editor for teams that ship words.", button: "Try Quill",
                items: ["Draft", "Review", "Publish", "Archive"], price: { "\(3 + $0 * 4) docs" })
        case "Harbor CRM":
            return .init(
                nav: ["Customers", "Deals", "Reports"], action: "Book a demo", headline: "Know every customer by name",
                line: "Notes, calls and follow-ups, kept where the team can see them.", button: "See the tour",
                items: ["Contacts", "Pipeline", "Tasks", "Inbox"], price: { "\(40 + $0 * 25) people" })
        case "Lanterna", "":
            return lanterna
        default:
            return .init(
                nav: ["Home", "Work", "About"], action: "Contact", headline: "\(name), made simple",
                line: "A made-up page for the demo.", button: "Learn more", items: ["One", "Two", "Three", "Four"],
                price: { "\($0 + 1)" })
        }
    }

    static let lanterna = DemoSiteContent(
        nav: ["Shop", "Stories", "About"], action: "Cart (2)", headline: "Light for every room",
        line: "Handmade lamps, shipped in three days.", button: "Shop the collection",
        items: ["Dune", "Halo", "Moth", "Ember"], price: { "$\(80 + $0 * 15)" })
}

/// A made-up web page: the stand-in for the running app's live view and for the pictures behind the cards.
struct DemoSitePage: View {
    let name: String
    let colour: ProjectColour
    // Drawn as a wide desktop page, so a frame shows it as a compact preview (details v2 mockup).
    private let design = CGSize(width: 1680, height: 1040)

    var body: some View {
        GeometryReader { g in
            page.frame(width: design.width, height: design.height)
                .scaleEffect(g.size.width / design.width, anchor: .topLeading)
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading).clipped()
        }
        .accessibilityHidden(true)
    }

    private var page: some View {
        let site = DemoSiteContent.of(name)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 28) {
                Text(name).font(.system(size: 22, weight: .bold))
                ForEach(site.nav, id: \.self) { Text($0).font(.system(size: 16)).opacity(0.6) }
                Spacer()
                Text(site.action).font(.system(size: 16))
            }
            .padding(.horizontal, 48).frame(height: 76)
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [colour.fill.opacity(0.9), colour.fill.opacity(0.45)], startPoint: .topLeading,
                    endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 14) {
                    Text(site.headline).font(.system(size: 54, weight: .bold))
                    Text(site.line).font(.system(size: 22)).opacity(0.85)
                    Text(site.button).font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 22).frame(height: 44)
                        .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.black)
                }
                .foregroundStyle(.white).padding(.horizontal, 48)
            }
            .frame(height: 340)
            HStack(spacing: 20) {
                ForEach(0..<4, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 10).fill(colour.fill.opacity(0.18 + Double(i) * 0.06)).frame(
                            height: 130)
                        Text(site.items[i]).font(.system(size: 16, weight: .semibold))
                        Text(site.price(i)).font(.system(size: 14)).opacity(0.6)
                    }
                }
            }
            .padding(48)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.12))
        .background(Color(red: 0.98, green: 0.97, blue: 0.95))
    }
}
