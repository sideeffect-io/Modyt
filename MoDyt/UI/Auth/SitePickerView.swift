import SwiftUI
import MoDytCore

struct SitePickerView: View {
    let sites: [SiteInfo]
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Select a site")
                .font(.title2.bold())

            List(sites.indices, id: \.self) { index in
                let site = sites[index]
                Button {
                    onSelect(index)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(site.name)
                            .font(.headline)
                        if let gateway = site.gateways.first {
                            Text(gateway.name ?? gateway.mac)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .frame(height: min(320, CGFloat(max(1, sites.count)) * 60))
            .listStyle(.plain)
        }
    }
}
