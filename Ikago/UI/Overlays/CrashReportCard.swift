import SwiftUI

/// Asks, after Ikago quit unexpectedly, whether to report it (`CrashReports`): at the top right of the window,
/// like the other cards there. Yes saves the report to Downloads and shows it in Finder; nothing is sent.
struct CrashReportCard: View {
    let reports: CrashReports
    let colors: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ikago quit unexpectedly").font(.system(size: 13, weight: .semibold))
                    Text("Save a crash report to Downloads, without your name or home folder? Then send it to the "
                         + "developer: attach it to a new issue on Ikago’s GitHub page, or share it another way. "
                         + "Nothing is sent by itself.")
                        .font(.system(size: 12)).foregroundStyle(colors.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                if reports.saving { ProgressView().controlSize(.small) }
                Spacer()
                Button("Not Now") { reports.dismiss() }.buttonStyle(SettingsButtonStyle()).disabled(reports.saving)
                Button(reports.saving ? "Saving…" : "Save Report") { reports.report() }
                .buttonStyle(SettingsButtonStyle(prominent: true)).disabled(reports.saving)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 360)
        .foregroundStyle(colors.text)
        .modalSurface(colors, radius: Radius.card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ikago quit unexpectedly")
    }
}
