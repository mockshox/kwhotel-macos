import AppKit
import UniformTypeIdentifiers

/// Wizard for setup.sh. Welcome, the KWHotel installer, then the install itself.

private func localized(_ polish: String, _ english: String) -> String {
    let language = Locale.preferredLanguages.first ?? "en"
    return language.hasPrefix("pl") ? polish : english
}

private enum Step {
    case welcome, installer, review, progress, finish
}

private enum Job {
    case install, launch, uninstall
}

final class InstallerController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let root: URL
    private let setupURL: URL
    private let uninstallURL: URL

    private var window: NSWindow!
    private var pageHost: NSView!
    private var pages: [Step: NSView] = [:]
    private var stepLabels: [NSTextField] = []
    private var backButton: NSButton!
    private var nextButton: NSButton!
    private var launchButton: NSButton!
    private var uninstallButton: NSButton!
    private var welcomeBody: NSTextField!
    private var fileNameLabel: NSTextField!
    private var filePathLabel: NSTextField!
    private var summaryName: NSTextField!
    private var progressStatus: NSTextField!
    private var progressIndicator: NSProgressIndicator!
    private var progressUnits: Double = 0
    private var finishTitle: NSTextField!
    private var finishBody: NSTextField!
    private var openCheckbox: NSButton!
    private var openingApp = false
    private var logView: NSTextView!

    private var step: Step = .welcome
    private var installerURL: URL?
    private var running = false
    private var failed = false
    private var ready = false
    private var hasRemnants = false
    private var job: Job = .install
    private var activeProcess: Process?

    init(root: URL) {
        self.root = root
        setupURL = root.appendingPathComponent("setup.sh")
        uninstallURL = root.appendingPathComponent("uninstall.sh")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard FileManager.default.isExecutableFile(atPath: setupURL.path),
              FileManager.default.isExecutableFile(atPath: uninstallURL.path) else {
            let alert = NSAlert()
            alert.messageText = localized(
                "Instalator jest niekompletny.",
                "The installer is incomplete."
            )
            alert.informativeText = localized(
                "W paczce brakuje skryptów instalacji. Pobierz KWHotel for MacOS jeszcze raz.",
                "This copy is missing its setup scripts. Download KWHotel for MacOS again."
            )
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        buildMenu()
        installerURL = bundledInstaller()
        refreshInstalledState()
        buildWindow()
        show(.welcome)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if running {
            let alert = NSAlert()
            alert.messageText = localized("Instalacja nadal trwa.", "Setup is still running.")
            alert.informativeText = localized(
                "To okno pokazuje postęp. Zostaw je otwarte do końca.",
                "This window shows the progress. Leave it open until setup finishes."
            )
            alert.runModal()
            return false
        }
        if openingApp {
            return true
        }
        if step == .finish, job == .install, openCheckbox.state == .on {
            openKWHotelThenQuit()
            return false
        }
        return true
    }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: localized("Zakończ KWHotel for MacOS", "Quit KWHotel for MacOS"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appItem.submenu = appMenu
        NSApp.mainMenu = menu
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "KWHotel for MacOS"
        window.delegate = self
        window.minSize = NSSize(width: 640, height: 460)
        guard let content = window.contentView else { return }

        let logo = makeLogo(width: 168, height: 112)
        logo.setAccessibilityLabel("KWHotel for MacOS")
        let header = NSStackView(views: [logo, makeStepBar()])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 20
        header.edgeInsets = NSEdgeInsets(top: 18, left: 24, bottom: 10, right: 24)

        let headerRule = NSBox()
        headerRule.boxType = .separator

        pageHost = NSView()
        pages[.welcome] = makeWelcomePage()
        pages[.installer] = makeInstallerPage()
        pages[.review] = makeReviewPage()
        pages[.progress] = makeProgressPage()
        pages[.finish] = makeFinishPage()

        let footerRule = NSBox()
        footerRule.boxType = .separator

        backButton = NSButton(title: localized("Wstecz", "Back"), target: self, action: #selector(backPressed))
        backButton.bezelStyle = .rounded
        if let image = symbol("chevron.left") {
            backButton.image = image
            backButton.imagePosition = .imageLeading
        }

        uninstallButton = NSButton(
            title: localized("Odinstaluj…", "Uninstall…"),
            target: self,
            action: #selector(confirmUninstall)
        )
        uninstallButton.bezelStyle = .rounded

        launchButton = NSButton(
            title: localized("Uruchom", "Launch"),
            target: self,
            action: #selector(launchInstalled)
        )
        launchButton.bezelStyle = .rounded

        nextButton = NSButton(title: localized("Dalej", "Next"), target: self, action: #selector(nextPressed))
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"
        applyForwardChevron()

        let leftButtons = NSStackView(views: [backButton, uninstallButton])
        leftButtons.orientation = .horizontal
        leftButtons.spacing = 8
        leftButtons.detachesHiddenViews = true
        let rightButtons = NSStackView(views: [launchButton, nextButton])
        rightButtons.orientation = .horizontal
        rightButtons.spacing = 8
        rightButtons.detachesHiddenViews = true
        let spacer = NSView()
        let footer = NSStackView(views: [leftButtons, spacer, rightButtons])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 16, right: 20)
        footer.detachesHiddenViews = true

        let column = NSStackView(views: [header, headerRule, pageHost, footerRule, footer])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 0
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)

        [header, headerRule, pageHost, footerRule, footer, logo, column].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        pageHost.setContentHuggingPriority(.defaultLow, for: .vertical)
        pageHost.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            column.topAnchor.constraint(equalTo: content.topAnchor),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            header.widthAnchor.constraint(equalTo: column.widthAnchor),
            headerRule.widthAnchor.constraint(equalTo: column.widthAnchor),
            pageHost.widthAnchor.constraint(equalTo: column.widthAnchor),
            footerRule.widthAnchor.constraint(equalTo: column.widthAnchor),
            footer.widthAnchor.constraint(equalTo: column.widthAnchor),
            nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 112),
            backButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 112)
        ])
        window.defaultButtonCell = nextButton.cell as? NSButtonCell
    }

    private func makeLogo(width: CGFloat, height: CGFloat) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(contentsOf: logoFile())
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.white.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    private func logoFile() -> URL {
        let bundled = root.appendingPathComponent("logo.jpg")
        if FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return root.appendingPathComponent("assets/logo.jpg")
    }

    private func makeStepBar() -> NSView {
        let names = [
            localized("Powitanie", "Welcome"),
            localized("Konfiguracja", "Configure"),
            localized("Instalacja", "Install"),
            localized("Koniec", "Done")
        ]
        var views: [NSView] = []
        for (index, name) in names.enumerated() {
            if index > 0 {
                let chevron = NSTextField(labelWithString: "›")
                chevron.font = .systemFont(ofSize: 15, weight: .semibold)
                chevron.textColor = .tertiaryLabelColor
                views.append(chevron)
            }
            let label = NSTextField(labelWithString: name)
            label.font = .systemFont(ofSize: 13, weight: .regular)
            stepLabels.append(label)
            views.append(label)
        }
        let bar = NSStackView(views: views)
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 10
        return bar
    }

    private func makeWelcomePage() -> NSView {
        let title = heading("KWHotel for MacOS")
        title.alignment = .center
        welcomeBody = wrapping(localized(
            "Ten instalator uruchamia windowsowy KWHotel na Macu. Dalej prowadzi przez wybór pliku .exe i instalację Wine oraz .NET Framework. Pierwsze uruchomienie potrzebuje sieci i około 8 GB wolnego miejsca.",
            "This installer runs the Windows KWHotel desktop on a Mac. Next walks through the .exe and the Wine and .NET Framework setup. The first run needs a network connection and about 8 GB free."
        ))
        welcomeBody.alignment = .center
        welcomeBody.preferredMaxLayoutWidth = 460
        let stack = NSStackView(views: [title, welcomeBody])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        welcomeBody.translatesAutoresizingMaskIntoConstraints = false
        welcomeBody.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return centered(stack, textWidth: 460)
    }

    private func makeInstallerPage() -> NSView {
        let title = heading(localized("Wskaż instalator", "Choose the installer"))
        let intro = wrapping(localized(
            "Wybierz pobrany plik KWHotel .exe. Może leżeć w Pobranych albo na Biurku.",
            "Choose the KWHotel .exe you downloaded. It may be in Downloads or on the Desktop."
        ))
        fileNameLabel = NSTextField(labelWithString: localized("Nie wybrano pliku", "No file selected"))
        fileNameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        fileNameLabel.lineBreakMode = .byTruncatingMiddle
        filePathLabel = NSTextField(wrappingLabelWithString: "")
        filePathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        filePathLabel.textColor = .secondaryLabelColor
        filePathLabel.maximumNumberOfLines = 2
        let nameStack = NSStackView(views: [fileNameLabel, filePathLabel])
        nameStack.orientation = .vertical
        nameStack.alignment = .leading
        nameStack.spacing = 4
        let well = NSBox()
        well.boxType = .custom
        well.cornerRadius = 10
        well.borderWidth = 1
        well.borderColor = .separatorColor
        well.fillColor = .controlBackgroundColor
        well.contentViewMargins = NSSize(width: 14, height: 12)
        nameStack.translatesAutoresizingMaskIntoConstraints = false
        if let wellContent = well.contentView {
            wellContent.addSubview(nameStack)
            NSLayoutConstraint.activate([
                nameStack.leadingAnchor.constraint(equalTo: wellContent.leadingAnchor),
                nameStack.trailingAnchor.constraint(equalTo: wellContent.trailingAnchor),
                nameStack.topAnchor.constraint(equalTo: wellContent.topAnchor),
                nameStack.bottomAnchor.constraint(equalTo: wellContent.bottomAnchor)
            ])
        }
        let choose = NSButton(
            title: localized("Wybierz plik…", "Choose File…"),
            target: self,
            action: #selector(chooseInstaller)
        )
        choose.bezelStyle = .rounded
        choose.keyEquivalent = "o"
        choose.keyEquivalentModifierMask = .command
        let stack = NSStackView(views: [title, intro, well, choose])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        well.translatesAutoresizingMaskIntoConstraints = false
        intro.translatesAutoresizingMaskIntoConstraints = false
        well.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        intro.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return padded(stack, stretching: nil)
    }

    private func makeReviewPage() -> NSView {
        let title = heading(localized("Można instalować", "Ready to install"))
        let intro = wrapping(localized(
            "Dalej pobierze brakujące składniki. To może potrwać kilka minut. KWHotel uruchomisz przy zamykaniu instalatora.",
            "Next downloads anything still missing. This can take several minutes. You can open KWHotel when you close the installer."
        ))
        summaryName = NSTextField(labelWithString: "—")
        summaryName.font = .systemFont(ofSize: 13, weight: .medium)
        summaryName.lineBreakMode = .byTruncatingMiddle
        let rows = NSStackView(views: [
            reviewRow(localized("Instalator", "Installer"), summaryName),
            reviewRow(localized("Wine", "Wine"), fixedValue("Crossover 23.7.1")),
            reviewRow(localized(".NET", ".NET"), fixedValue("Framework 4.8")),
            reviewRow(
                localized("Program", "Program"),
                fixedValue("~/Library/Application Support/KWHotel")
            )
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8
        let stack = NSStackView(views: [title, intro, rows])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        intro.translatesAutoresizingMaskIntoConstraints = false
        rows.translatesAutoresizingMaskIntoConstraints = false
        intro.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        rows.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return padded(stack, stretching: nil)
    }

    private func makeProgressPage() -> NSView {
        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .bar
        progressIndicator.controlSize = .regular
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1000
        progressIndicator.doubleValue = 0
        progressStatus = NSTextField(labelWithString: localized("Pracuję…", "Working…"))
        progressStatus.font = .systemFont(ofSize: 13, weight: .semibold)
        progressStatus.lineBreakMode = .byTruncatingTail

        logView = NSTextView()
        logView.isEditable = false
        logView.isSelectable = true
        logView.isRichText = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textColor = .labelColor
        logView.drawsBackground = true
        logView.backgroundColor = .textBackgroundColor
        logView.textContainerInset = NSSize(width: 8, height: 8)
        logView.isVerticallyResizable = true
        logView.isHorizontallyResizable = false
        logView.textContainer?.widthTracksTextView = true
        logView.minSize = NSSize(width: 0, height: 0)
        logView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        logView.autoresizingMask = [.width]

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.documentView = logView

        let logBox = NSBox()
        logBox.boxType = .custom
        logBox.cornerRadius = 10
        logBox.borderWidth = 1
        logBox.borderColor = .separatorColor
        logBox.fillColor = .textBackgroundColor
        logBox.contentViewMargins = NSSize(width: 0, height: 0)
        if let boxContent = logBox.contentView {
            scroll.translatesAutoresizingMaskIntoConstraints = false
            boxContent.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: boxContent.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: boxContent.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: boxContent.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: boxContent.bottomAnchor)
            ])
        }

        let stack = NSStackView(views: [progressStatus, progressIndicator, logBox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        progressStatus.setContentHuggingPriority(.defaultHigh, for: .vertical)
        progressIndicator.setContentHuggingPriority(.defaultHigh, for: .vertical)
        logBox.setContentHuggingPriority(.init(1), for: .vertical)
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressStatus.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        progressStatus.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return padded(stack, stretching: logBox)
    }

    private func makeFinishPage() -> NSView {
        let mark = NSImageView()
        mark.image = finishMark()
        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.widthAnchor.constraint(equalToConstant: 96).isActive = true
        mark.heightAnchor.constraint(equalToConstant: 96).isActive = true
        mark.setAccessibilityLabel(localized("Gotowe", "Done"))

        finishTitle = heading(localized("Gotowe", "Finished"))
        finishTitle.alignment = .center
        finishBody = wrapping("")
        finishBody.alignment = .center
        openCheckbox = NSButton(
            checkboxWithTitle: localized("Uruchom KWHotel", "Open KWHotel"),
            target: nil,
            action: nil
        )
        openCheckbox.state = .on
        let stack = NSStackView(views: [mark, finishTitle, finishBody, openCheckbox])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        return centered(stack, textWidth: 440)
    }

    private func finishMark() -> NSImage? {
        guard let base = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) else {
            return nil
        }
        let size = NSImage.SymbolConfiguration(pointSize: 88, weight: .regular)
        let colors = NSImage.SymbolConfiguration(paletteColors: [.white, .systemGreen])
        return base.withSymbolConfiguration(size.applying(colors))
    }

    private func heading(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 22, weight: .semibold)
        field.textColor = .labelColor
        return field
    }

    private func wrapping(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 13)
        field.textColor = .secondaryLabelColor
        field.maximumNumberOfLines = 4
        return field
    }

    private func fixedValue(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.lineBreakMode = .byTruncatingMiddle
        return field
    }

    private func reviewRow(_ title: String, _ value: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let row = NSStackView(views: [label, value])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        return row
    }

    private func padded(_ stack: NSStackView, stretching: NSView?) -> NSView {
        let page = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(stack)
        var constraints = [
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: 28)
        ]
        if let stretching {
            stretching.translatesAutoresizingMaskIntoConstraints = false
            constraints.append(stretching.widthAnchor.constraint(equalTo: stack.widthAnchor))
            stretching.setContentHuggingPriority(.init(1), for: .vertical)
            constraints.append(stack.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -20))
        }
        NSLayoutConstraint.activate(constraints)
        return page
    }

    private func centered(_ stack: NSStackView, textWidth: CGFloat) -> NSView {
        let page = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: page.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: page.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: page.widthAnchor, constant: -64),
            stack.widthAnchor.constraint(equalToConstant: textWidth).withPriority(.defaultHigh)
        ])
        return page
    }

    private func symbol(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    private func applyForwardChevron() {
        guard let image = symbol("chevron.right") else { return }
        nextButton.image = image
        nextButton.imagePosition = .imageTrailing
        if #available(macOS 13, *) {
            nextButton.imageHugsTitle = true
        }
    }

    private func show(_ next: Step) {
        step = next
        if next == .welcome {
            refreshInstalledState()
            updateWelcomeCopy()
        }
        if next == .review {
            summaryName.stringValue = installerURL?.lastPathComponent ?? "—"
        }
        if next == .installer {
            updateFileLabels()
        }
        pageHost.subviews.forEach { $0.removeFromSuperview() }
        guard let page = pages[next] else { return }
        page.translatesAutoresizingMaskIntoConstraints = false
        pageHost.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
            page.topAnchor.constraint(equalTo: pageHost.topAnchor),
            page.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor)
        ])
        highlightStep(index(of: next))
        updateChrome()
    }

    private func index(of step: Step) -> Int {
        switch step {
        case .welcome: return 0
        case .installer: return 1
        case .review, .progress: return 2
        case .finish: return 3
        }
    }

    private func highlightStep(_ index: Int) {
        for (item, label) in stepLabels.enumerated() {
            let current = item == index
            label.font = .systemFont(ofSize: 13, weight: current ? .semibold : .regular)
            if current {
                label.textColor = .controlAccentColor
            } else if item < index {
                label.textColor = .labelColor
            } else {
                label.textColor = .tertiaryLabelColor
            }
        }
    }

    private func updateChrome() {
        let onWelcome = step == .welcome
        let onFinish = step == .finish
        backButton.isHidden = onWelcome || onFinish
        launchButton.isHidden = !onWelcome || !ready
        uninstallButton.isHidden = !onWelcome || !hasRemnants
        backButton.isEnabled = !running && (step != .progress || failed)
        switch step {
        case .welcome:
            nextButton.title = localized("Dalej", "Next")
            applyForwardChevron()
            nextButton.isEnabled = true
        case .installer:
            nextButton.title = localized("Dalej", "Next")
            applyForwardChevron()
            nextButton.isEnabled = installerURL != nil && !running
        case .review:
            nextButton.title = localized("Dalej", "Next")
            applyForwardChevron()
            nextButton.isEnabled = installerURL != nil && !running
        case .progress:
            nextButton.title = localized("Dalej", "Next")
            applyForwardChevron()
            nextButton.isEnabled = false
        case .finish:
            nextButton.image = nil
            nextButton.title = job == .uninstall
                ? localized("Gotowe", "Done")
                : localized("Zakończ", "Finish")
            nextButton.isEnabled = true
        }
        window.defaultButtonCell = nextButton.cell as? NSButtonCell
    }

    private func updateWelcomeCopy() {
        if ready {
            welcomeBody.stringValue = localized(
                "KWHotel jest już na tym Macu. Uruchom go albo wybierz Dalej, żeby zainstalować od nowa.",
                "KWHotel is already on this Mac. Launch it, or choose Next to set it up again."
            )
        } else {
            welcomeBody.stringValue = localized(
                "Ten instalator uruchamia windowsowy KWHotel na Macu. Dalej prowadzi przez wybór pliku .exe i instalację Wine oraz .NET Framework. Pierwsze uruchomienie potrzebuje sieci i około 8 GB wolnego miejsca.",
                "This installer runs the Windows KWHotel desktop on a Mac. Next walks through the .exe and the Wine and .NET Framework setup. The first run needs a network connection and about 8 GB free."
            )
        }
    }

    private func updateFileLabels() {
        if let installerURL {
            fileNameLabel.stringValue = installerURL.lastPathComponent
            fileNameLabel.textColor = .labelColor
            filePathLabel.stringValue = installerURL.deletingLastPathComponent().path
        } else {
            fileNameLabel.stringValue = localized("Nie wybrano pliku", "No file selected")
            fileNameLabel.textColor = .secondaryLabelColor
            filePathLabel.stringValue = ""
        }
    }

    private func refreshInstalledState() {
        ready = installationIsReady()
        hasRemnants = ready || directoryExists(supportDirectory()) || directoryExists(prefixDirectory())
    }

    private func supportDirectory() -> String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/KWHotel")
    }

    private func prefixDirectory() -> String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".wine-kwhotel")
    }

    private func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func installationIsReady() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c",
            "ROOT=\"$1\"; source \"$1/lib/kwhotel.sh\"; is_ready",
            "kwhotel",
            root.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func bundledInstaller() -> URL? {
        let directories = [
            root.appendingPathComponent("installer"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("installer")
        ]
        for directory in directories {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else { continue }
            if let match = items
                .filter({
                    $0.lastPathComponent.hasPrefix("KWHotel")
                        && $0.pathExtension.lowercased() == "exe"
                })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                .first {
                return match
            }
        }
        return nil
    }

    @objc private func nextPressed() {
        switch step {
        case .welcome:
            show(.installer)
        case .installer:
            guard installerURL != nil else { return }
            show(.review)
        case .review:
            guard let installerURL else { return }
            job = .install
            run(
                script: setupURL,
                arguments: [],
                environment: [
                    "KWHOTEL_INSTALLER": installerURL.path,
                    "KWHOTEL_REINSTALL": "1"
                ]
            )
        case .progress:
            break
        case .finish:
            if job == .uninstall {
                show(.welcome)
            } else if job == .install, openCheckbox.state == .on {
                openKWHotelThenQuit()
            } else {
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func backPressed() {
        guard !running else { return }
        switch step {
        case .installer:
            show(.welcome)
        case .review:
            show(.installer)
        case .progress where failed:
            show(job == .install ? .review : .welcome)
        default:
            break
        }
    }

    @objc private func chooseInstaller() {
        let panel = NSOpenPanel()
        panel.title = localized("Instalator KWHotel", "KWHotel installer")
        panel.message = localized(
            "Wskaż pobrany plik KWHotel*.exe.",
            "Choose the downloaded KWHotel*.exe file."
        )
        panel.prompt = localized("Wybierz", "Choose")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let exeType = UTType(filenameExtension: "exe") {
            panel.allowedContentTypes = [exeType]
        }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.acceptInstaller(url)
        }
    }

    private func acceptInstaller(_ url: URL) {
        let name = url.lastPathComponent
        let looksLikeKWHotel = name.range(of: "kwhotel", options: .caseInsensitive) != nil
        if !looksLikeKWHotel {
            let alert = NSAlert()
            alert.messageText = localized(
                "Ten plik nie ma w nazwie KWHotel.",
                "This file name does not contain KWHotel."
            )
            alert.informativeText = name
            alert.addButton(withTitle: localized("Użyj go", "Use it"))
            alert.addButton(withTitle: localized("Anuluj", "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        installerURL = url
        updateFileLabels()
        updateChrome()
    }

    @objc private func launchInstalled() {
        job = .launch
        run(script: setupURL, arguments: ["--launch-only"], environment: ["KWHOTEL_REINSTALL": "0"])
    }

    @objc private func confirmUninstall() {
        let alert = NSAlert()
        alert.messageText = localized("Odinstalować KWHotel?", "Uninstall KWHotel?")
        alert.informativeText = localized(
            "Znikną prefiks Wine, .NET Framework i pliki programu. Folder projektu oraz instalator .exe zostaną.",
            "The Wine prefix, .NET Framework, and program files will be removed. The project folder and the .exe installer stay."
        )
        alert.addButton(withTitle: localized("Odinstaluj", "Uninstall"))
        alert.addButton(withTitle: localized("Anuluj", "Cancel"))
        alert.alertStyle = .warning

        let keepData = NSButton(
            checkboxWithTitle: localized(
                "Zachowaj bazę hotelu i ustawienia",
                "Keep the hotel database and settings"
            ),
            target: nil,
            action: nil
        )
        keepData.state = .on
        let keepWine = NSButton(
            checkboxWithTitle: localized("Zachowaj Wine Crossover", "Keep Wine Crossover"),
            target: nil,
            action: nil
        )
        keepWine.state = .off
        let options = NSStackView(views: [keepData, keepWine])
        options.orientation = .vertical
        options.alignment = .leading
        options.spacing = 6
        options.frame = NSRect(x: 0, y: 0, width: 380, height: 48)
        alert.accessoryView = options
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        job = .uninstall
        var arguments = ["--yes"]
        if keepData.state == .on { arguments.append("--keep-data") }
        if keepWine.state == .on { arguments.append("--keep-wine") }
        run(script: uninstallURL, arguments: arguments, environment: [:])
    }

    private func run(script: URL, arguments: [String], environment: [String: String]) {
        guard !running else { return }
        running = true
        failed = false
        logView.string = ""
        progressStatus.stringValue = localized("Pracuję…", "Working…")
        resetProgress()
        show(.progress)

        let process = Process()
        process.executableURL = script
        process.arguments = arguments
        process.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "KWHOTEL_INSTALLER")
        env["KWHOTEL_LANG"] = (Locale.preferredLanguages.first ?? "").hasPrefix("pl") ? "pl" : "en"
        environment.forEach { env[$0.key] = $0.value }
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        activeProcess = process
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return
            }
            self?.appendLog(text)
        }
        process.terminationHandler = { [weak self] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            let remainder = pipe.fileHandleForReading.readDataToEndOfFile()
            let status = finished.terminationStatus
            DispatchQueue.main.async {
                guard let self else { return }
                if let text = String(data: remainder, encoding: .utf8) ?? String(data: remainder, encoding: .isoLatin1),
                   !text.isEmpty {
                    self.appendLog(text)
                }
                self.running = false
                self.activeProcess = nil
                self.refreshInstalledState()
                if status == 0 {
                    self.failed = false
                    self.advanceProgress(to: 1000, status: nil)
                    self.presentFinish()
                } else {
                    self.failed = true
                    self.progressStatus.stringValue = localized(
                        "Polecenie zakończyło się błędem (\(status)). Wróć i spróbuj ponownie.",
                        "The command failed (\(status)). Go back and try again."
                    )
                    self.updateChrome()
                }
            }
        }
        do {
            try process.run()
        } catch {
            running = false
            failed = true
            progressStatus.stringValue = error.localizedDescription
            updateChrome()
        }
    }

    private func presentFinish() {
        switch job {
        case .install:
            finishTitle.stringValue = localized("KWHotel jest gotowy", "KWHotel is ready")
            finishBody.stringValue = localized(
                "Możesz zamknąć instalator.",
                "You can close the installer."
            )
            openCheckbox.state = .on
            openCheckbox.isHidden = false
        case .launch:
            finishTitle.stringValue = localized("KWHotel jest gotowy", "KWHotel is ready")
            finishBody.stringValue = localized(
                "Program się uruchamia. To okno można zamknąć.",
                "The program is starting. You can close this window."
            )
            openCheckbox.isHidden = true
        case .uninstall:
            finishTitle.stringValue = localized("KWHotel został usunięty", "KWHotel was removed")
            finishBody.stringValue = localized(
                "Prefiks Wine i pliki programu zostały usunięte. Folder projektu został na miejscu.",
                "The Wine prefix and program files were removed. The project folder is still here."
            )
            openCheckbox.isHidden = true
        }
        show(.finish)
    }

    private func openKWHotelThenQuit() {
        if openingApp { return }
        openingApp = true
        nextButton.isEnabled = false
        openCheckbox.isEnabled = false
        let process = Process()
        process.executableURL = setupURL
        process.arguments = ["--launch-only"]
        process.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "KWHOTEL_INSTALLER")
        env["KWHOTEL_REINSTALL"] = "0"
        process.environment = env
        process.terminationHandler = { _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        do {
            try process.run()
        } catch {
            NSApp.terminate(nil)
        }
    }

    private func appendLog(_ text: String) {
        let apply = {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
            self.logView.textStorage?.append(NSAttributedString(string: text, attributes: attributes))
            if let storage = self.logView.textStorage, storage.length > 200_000 {
                storage.deleteCharacters(in: NSRange(location: 0, length: storage.length - 150_000))
            }
            self.logView.scrollToEndOfDocument(nil)
            self.noteProgress(in: text)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func resetProgress() {
        progressUnits = 40
        progressIndicator.isIndeterminate = false
        progressIndicator.doubleValue = progressUnits
    }

    private func advanceProgress(to units: Double, status: (String, String)?) {
        let next = min(1000, max(progressUnits, units))
        progressUnits = next
        progressIndicator.doubleValue = next
        if let status {
            progressStatus.stringValue = localized(status.0, status.1)
        }
    }

    private func noteProgress(in text: String) {
        if job == .uninstall {
            advanceProgress(to: min(900, progressUnits + 30), status: nil)
            return
        }
        let lower = text.lowercased()
        let stages: [(String, Double, String, String)] = [
            ("kwhotel macos setup", 80, "Przygotowanie…", "Preparing…"),
            ("installing rosetta", 140, "Instaluję Rosettę…", "Installing Rosetta…"),
            ("downloading", 220, "Pobieranie…", "Downloading…"),
            ("installing wine", 320, "Instaluję Wine…", "Installing Wine…"),
            ("creating wine prefix", 400, "Tworzę prefiks Wine…", "Creating the Wine prefix…"),
            ("installing .net framework", 480, "Instaluję .NET Framework…", "Installing .NET Framework…"),
            ("dotnet40", 560, "Instaluję .NET Framework…", "Installing .NET Framework…"),
            ("dotnet48", 740, "Instaluję .NET Framework 4.8…", "Installing .NET Framework 4.8…"),
            ("already installed (release", 820, "Sprawdzam składniki…", "Checking components…"),
            ("extracting", 900, "Rozpakowuję KWHotel…", "Extracting KWHotel…"),
            ("starting kwhotel", 960, "Uruchamiam KWHotel…", "Starting KWHotel…"),
            ("ready. app", 1000, "Gotowe", "Ready")
        ]
        var target = progressUnits
        var label: (String, String)?
        for (needle, units, polish, english) in stages {
            if lower.contains(needle), units >= target {
                target = units
                label = (polish, english)
            }
        }
        if target == progressUnits && (lower.contains("executing") || lower.contains("warning:")) {
            target = min(860, progressUnits + 6)
        }
        advanceProgress(to: target, status: label)
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

private func projectRoot() -> URL {
    if let resources = Bundle.main.resourceURL {
        let setup = resources.appendingPathComponent("setup.sh")
        if FileManager.default.isExecutableFile(atPath: setup.path) {
            return resources
        }
    }
    return Bundle.main.bundleURL.deletingLastPathComponent()
}

let app = NSApplication.shared
let controller = InstallerController(root: projectRoot())
app.setActivationPolicy(.regular)
app.delegate = controller
app.run()
