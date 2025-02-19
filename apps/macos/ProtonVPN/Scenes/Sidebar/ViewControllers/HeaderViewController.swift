//
//  HeaderViewController.swift
//  ProtonVPN - Created on 27.06.19.
//
//  Copyright (c) 2019 Proton Technologies AG
//
//  This file is part of ProtonVPN.
//
//  ProtonVPN is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ProtonVPN is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with ProtonVPN.  If not, see <https://www.gnu.org/licenses/>.
//

import Cocoa
import SDWebImage
import vpncore

final class HeaderViewController: NSViewController {

    @IBOutlet private weak var backgroundView: NSView!
    @IBOutlet private weak var flagView: FlagView!
    @IBOutlet private weak var headerLabel: NSTextField!
    @IBOutlet private weak var ipLabel: NSTextField!
    @IBOutlet private weak var loadLabel: NSTextField!
    @IBOutlet private weak var loadIcon: LoadCircle!
    @IBOutlet private weak var speedLabel: NSTextField!
    @IBOutlet private weak var connectButton: LargeConnectButton!
    @IBOutlet private weak var announcementsButton: NSButton!
    @IBOutlet private weak var loadLineHorizontalConstraint1: NSLayoutConstraint!
    @IBOutlet private weak var loadLineHorizontalConstraint2: NSLayoutConstraint!
    @IBOutlet private weak var loadLineHorizontalConstraint3: NSLayoutConstraint!
    @IBOutlet private weak var loadLineHorizontalConstraint4: NSLayoutConstraint!
    @IBOutlet private weak var protocolLabel: NSTextField!
    @IBOutlet private weak var badgeView: NSView!

    var announcementsButtonPressed: (() -> Void)?
    
    private var loadLineHorizontalConstraints: [NSLayoutConstraint] {
        return [loadLineHorizontalConstraint1, loadLineHorizontalConstraint2, loadLineHorizontalConstraint3, loadLineHorizontalConstraint4]
    }
    
    private var viewModel: HeaderViewModel!
    
    required init?(coder: NSCoder) {
        fatalError("Unsupported initializer")
    }
    
    required init(viewModel: HeaderViewModel) {
        super.init(nibName: NSNib.Name("Header"), bundle: nil)
        self.viewModel = viewModel
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        viewModel.delegate = self
        setupPersistentView()
        setupEphemeralView()
        viewModel.contentChanged = { [weak self] in self?.setupEphemeralView() }
        
        setupAnnouncements()
        NotificationCenter.default.addObserver(self, selector: #selector(setupAnnouncements), name: AnnouncementStorageNotifications.contentChanged, object: nil)
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        setupAnnouncements()
    }
    
    private func setupPersistentView() {
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.protonDarkGrey().cgColor
                
        connectButton.target = self
        connectButton.action = #selector(quickConnectButtonAction)
    }
    
    private func setupEphemeralView() {
        setupFlagView()
        
        headerLabel.attributedStringValue = viewModel.headerLabel
        ipLabel.attributedStringValue = viewModel.ipLabel
        
        setupLoad()
        setupProtocol()
        setupBitrate()
        
        connectButton.isConnected = viewModel.isConnected
    }
    
    private func setupFlagView() {
        if viewModel.isConnected, let countryCode = viewModel.connectedCountryCode?.lowercased() {
            flagView.backgroundImage = NSImage(named: NSImage.Name("\(countryCode)-large"))
        } else if !viewModel.isConnected && flagView.backgroundImage != nil {
            flagView.backgroundImage = nil
        }
    }
    
    private func setupLoad() {
        if viewModel.isConnected, let loadDescription = viewModel.loadLabel, let loadDescriptionShort = viewModel.loadLabelShort, let loadPercentage = viewModel.loadPercentage {
            loadLabel.attributedStringValue = loadDescription // Preset with full description for `loadLineType` to work correctly
            loadLabel.toolTip = ""
            if loadLineType == .short {
                loadLabel.attributedStringValue = loadDescriptionShort
                loadLabel.toolTip = loadDescription.string
            }
            loadLabel.isHidden = false
            loadIcon.load = loadPercentage
            loadIcon.toolTip = loadDescription.string
            loadIcon.isHidden = false
        } else {
            loadLabel.isHidden = true
            loadIcon.isHidden = true
        }
    }

    private func setupProtocol() {
        guard viewModel.isConnected, let vpnProcol = viewModel.vpnProtocol else {
            protocolLabel.isHidden = true
            return
        }

        protocolLabel.isHidden = false
        protocolLabel.attributedStringValue = vpnProcol
    }
    
    private func setupBitrate() {
        if viewModel.isConnected {
            speedLabel.isHidden = false
        } else {
            speedLabel.isHidden = true
        }
    }
    
    @objc private func quickConnectButtonAction() {
        viewModel.quickConnectAction()
    }
    
    // MARK: Announcements
    
    @objc func setupAnnouncements() {
        badgeView.wantsLayer = true
        badgeView.layer?.cornerRadius = 3
        badgeView.layer?.backgroundColor = NSColor.protonRed().cgColor
        badgeView.isHidden = true

        guard let viewModel = viewModel, viewModel.showAnnouncements else {
            announcementsButton.isHidden = true
            return
        }

        let setup = { [weak self] (image: NSImage?) in
            self?.announcementsButton.image = image
            self?.announcementsButton.isHidden = false
            self?.badgeView.isHidden = self?.viewModel.hasUnreadAnnouncements != true
        }

        announcementsButton.toolTip = viewModel.announcementTooltip
        announcementsButton.isHidden = true
        guard let iconUrl = viewModel.announcementIconUrl else {
            setup(NSImage(named: "bell"))
            return
        }

        if let cached = SDImageCache.shared.imageFromCache(forKey: iconUrl.absoluteString) {
            setup(cached)
            return
        }

        let downloader = SDWebImageDownloader()
        downloader.downloadImage(with: iconUrl) { [weak self] (image, _, _, _) in
            if let icon = image {
                SDImageCache.shared.store(icon, forKey: iconUrl.absoluteString, completion: nil)
                setup(icon)
            } else if self?.announcementsButton.image == nil {
                setup(NSImage(named: "bell"))
            }
        }
    }
    
    @IBAction private func announcementsButtonTapped(_ sender: Any) {
        announcementsButtonPressed?()
    }
    
    // MARK: Load line
    
    private enum LineType {
        case full
        case short
    }
    
    private var loadLineType: LineType {
        let margins = loadLineHorizontalConstraints.reduce(0.0) { $0 + $1.constant }
        let width = margins + ipLabel.intrinsicContentSize.width + loadLabel.intrinsicContentSize.width + loadIcon.frame.width
        
        debugPrint(margins, ipLabel.intrinsicContentSize.width, loadLabel.intrinsicContentSize.width, loadIcon.frame.width, width, self.view.frame.width)
        if width + 10 > self.view.frame.width {
            return .short
        }
        return .full
    }
    
}

extension HeaderViewController: HeaderViewModelDelegate {
    func bitrateUpdated(with attributedString: NSAttributedString) {
        speedLabel.attributedStringValue = attributedString
    }
}
