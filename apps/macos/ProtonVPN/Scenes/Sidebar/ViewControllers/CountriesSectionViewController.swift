//
//  CountriesSectionViewController.swift
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
import vpncore

class CountriesSectionViewController: NSViewController {

    fileprivate enum Cell: String {
        case country = "CountryItemCellView"
        case server = "ServerItemCellView"
        case header = "CountriesSectionHeaderView"
        
        var identifier: NSUserInterfaceItemIdentifier {
            return NSUserInterfaceItemIdentifier(self.rawValue)
        }
        
        var nib: NSNib? {
            return NSNib(nibNamed: NSNib.Name(self.rawValue), bundle: nil)
        }
    }
    
    enum QuickSettingType {
        case secureCoreDisplay
        case netShieldDisplay
        case killSwitchDisplay
    }

    @IBOutlet weak var searchIcon: NSImageView!
    @IBOutlet weak var searchTextField: TextFieldWithFocus!
    @IBOutlet weak var bottomHorizontalLine: NSBox!
    @IBOutlet weak var serverListScrollView: BlockeableScrollView!
    @IBOutlet weak var serverListTableView: NSTableView!
    @IBOutlet weak var shadowView: ShadowView!
    @IBOutlet weak var clearSearchBtn: NSButton!
    
    @IBOutlet weak var quickSettingsStack: NSStackView!
    @IBOutlet weak var secureCoreSectionView: NSView!
    @IBOutlet weak var netShieldSectionView: NSView!
    @IBOutlet weak var killSwitchSectionView: NSView!
    
    @IBOutlet weak var netShieldBox: NSBox!
    
    @IBOutlet weak var secureCoreBtn: QuickSettingButton!
    @IBOutlet weak var netShieldBtn: QuickSettingButton!
    @IBOutlet weak var killSwitchBtn: QuickSettingButton!
    
    @IBOutlet weak var listTrailingConstraint: NSLayoutConstraint!
    @IBOutlet weak var listLeadingConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var secureCoreContainer: NSBox!
    @IBOutlet weak var netshieldContainer: NSBox!
    @IBOutlet weak var killSwitchContainer: NSBox!
        
    fileprivate let viewModel: CountriesSectionViewModel
    
    private var infoButtonRowSelected: Int?
    private var serverInfoViewController: ServerInfoViewController?
    private var quickSettingDetailDisplayed = false
    
    weak var sidebarView: NSView?
    
    required init?(coder: NSCoder) {
        fatalError("Unsupported initializer")
    }
    
    required init(viewModel: CountriesSectionViewModel) {
        self.viewModel = viewModel
        super.init(nibName: NSNib.Name("CountriesSection"), bundle: nil)
        viewModel.delegate = self
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupSearchSection()
        setupTableView()
        setupQuickSettings()
        
        guard #available(OSX 11, *) else {
            // quickfix for older versions than big sur
            listLeadingConstraint.constant = 0
            listTrailingConstraint.constant = 0
            return
        }
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        didDisplayQuickSetting(appear: false)
    }
    
    override func viewDidLayout() {
        netShieldBtn.layoutSubtreeIfNeeded()
        secureCoreBtn.layoutSubtreeIfNeeded()
        killSwitchBtn.layoutSubtreeIfNeeded()
    }
    
    private func setupView() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.protonGrey().cgColor
    }
        
    private func setupSearchSection() {
        bottomHorizontalLine.fillColor = .protonLightGrey()
        
        searchIcon.image = NSImage(named: NSImage.Name("search"))
        
        clearSearchBtn.target = self
        clearSearchBtn.action = #selector(clearSearch)
        
        searchTextField.delegate = self
        searchTextField.usesSingleLineMode = true
        searchTextField.focusRingType = .none
        searchTextField.refusesFirstResponder = true
        searchTextField.textColor = .protonWhite()
        searchTextField.font = NSFont.systemFont(ofSize: 16)
        searchTextField.alignment = .left
        searchTextField.placeholderAttributedString = LocalizedString.searchForCountry.attributed(withColor: .protonGreyOutOfFocus(), fontSize: 16, alignment: .left)
    }
    
    private func setupTableView() {
        serverListTableView.dataSource = self
        serverListTableView.delegate = self
        serverListTableView.ignoresMultiClick = true
        serverListTableView.selectionHighlightStyle = .none
        serverListTableView.intercellSpacing = NSSize(width: 0, height: 0)
        serverListTableView.backgroundColor = .protonGrey()
        serverListTableView.register(Cell.country.nib, forIdentifier: Cell.country.identifier)
        serverListTableView.register(Cell.server.nib, forIdentifier: Cell.server.identifier)
        serverListTableView.register(Cell.header.nib, forIdentifier: Cell.header.identifier)
        
        serverListScrollView.backgroundColor = .protonGrey()
        shadowView.shadow(for: serverListScrollView.contentView.bounds.origin.y)
        serverListScrollView.contentView.postsBoundsChangedNotifications = true
        
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled(_:)), name: NSView.boundsDidChangeNotification, object: serverListScrollView.contentView)
        viewModel.contentChanged = { [weak self] change in self?.contentChanged(change) }
        viewModel.displayPremiumServices = { self.presentAsSheet(FeaturesOverlayViewController(viewModel: FeaturesOverlayViewModel())) }
        viewModel.displayStreamingServices = { self.presentAsSheet(StreamingServicesOverlayViewController(viewModel: StreamingServicesOverlayViewModel(country: $0, streamServices: $1, propertiesManager: $2))) }
    }
    
    private func setupQuickSettings() {
        [ (viewModel.secureCorePresenter, secureCoreContainer, secureCoreBtn, 0),
          (viewModel.netShieldPresenter, netshieldContainer, netShieldBtn, 1),
          (viewModel.killSwitchPresenter, killSwitchContainer, killSwitchBtn, 2) ].forEach { presenter, container, button, index in
            let vc = QuickSettingDetailViewController( presenter )
            vc.viewWillAppear()
            container?.addSubview(vc.view)
            vc.view.frame.size = NSSize(width: AppConstants.Windows.sidebarWidth, height: container?.frame.size.height ?? 0)
            vc.view.frame.origin = .zero
            button?.toolTip = presenter.title
            button?.callback = { _ in self.didTapSettingButton(index) }
            button?.detailOpened = false
            presenter.dismiss = {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.didDisplayQuickSetting(appear: false)
                }
            }
            self.addChild(vc)
        }
        netShieldBox.isHidden = !viewModel.isNetShieldEnabled
        viewModel.updateSettings()
    }
    
    private func showInfo(for row: Int, and view: NSView, with server: ServerModel) {
        guard let sidebarView = sidebarView else { return }
        
        let infoModel = ServerInfoViewModel(server: server)
        if let infoButtonRowSelected = infoButtonRowSelected,
           let serverInfoViewController = serverInfoViewController,
           sidebarView.subviews.contains(serverInfoViewController.view) {
            serverInfoViewController.removeFromParent()
            guard infoButtonRowSelected != row else {
                self.serverInfoViewController = nil
                return
            }
        }
        infoButtonRowSelected = row
        serverInfoViewController = ServerInfoViewController(viewModel: infoModel)
        
        let rowOrigin = self.view.convert(view.frame.origin, from: view)
        serverInfoViewController!.infoYPosition = rowOrigin.y + view.frame.height / 2
        serverInfoViewController!.view.frame = sidebarView.frame
        sidebarView.addSubview(serverInfoViewController!.view)
    }
    
    @objc private func scrolled(_ notification: Notification) {
        shadowView.shadow(for: serverListScrollView.contentView.bounds.origin.y)
    }
    
    @objc private func clearSearch() {
        if searchTextField.stringValue.isEmpty { return }
        searchTextField.stringValue = ""
        clearSearchBtn.isHidden = true
        viewModel.filterContent(forQuery: "")
    }
    
    private func didTapSettingButton( _ index: Int ) {
        switch index {
        case 0:
            let finalValue = secureCoreContainer.isHidden
            didDisplayQuickSetting(.secureCoreDisplay, appear: finalValue)
        case 1:
            let finalValue = netshieldContainer.isHidden
            didDisplayQuickSetting(.netShieldDisplay, appear: finalValue)
        default:
            let finalValue = killSwitchContainer.isHidden
            didDisplayQuickSetting(.killSwitchDisplay, appear: finalValue)
        }
    }
    
    private func didDisplayQuickSetting ( _ quickSettingItem: QuickSettingType? = nil, appear: Bool ) {
        
        let secureCoreDisplay = (quickSettingItem == .secureCoreDisplay) && appear
        let netShieldDisplay = (quickSettingItem == .netShieldDisplay) && appear
        let killSwitchDisplay = (quickSettingItem == .killSwitchDisplay) && appear
        
        searchTextField.isEnabled = !appear
        
        secureCoreBtn.detailOpened = secureCoreDisplay
        secureCoreContainer.isHidden = !secureCoreDisplay
        
        netShieldBtn.detailOpened = netShieldDisplay
        netshieldContainer.isHidden = !netShieldDisplay
        
        killSwitchBtn.detailOpened = killSwitchDisplay
        killSwitchContainer.isHidden = !killSwitchDisplay
        
        serverListScrollView.block = appear
        quickSettingDetailDisplayed = appear

        serverListTableView.reloadData()
    }

    private func contentChanged(_ contentChange: ContentChange) {
        
        if contentChange.reset {
            serverListTableView.reloadData()
            return
        }
        
        if let indexes = contentChange.reload {
            serverListTableView.reloadData(forRowIndexes: indexes, columnIndexes: IndexSet([0]))
            return
        }
        
        let shouldAnimate = contentChange.insertedRows == nil || contentChange.removedRows == nil
        
        serverListTableView.beginUpdates()
        if let removedRows = contentChange.removedRows {
            serverListTableView.removeRows(at: removedRows, withAnimation: shouldAnimate ? [NSTableView.AnimationOptions.slideUp] : [])
        }
        
        if let insertedRows = contentChange.insertedRows {
            serverListTableView.insertRows(at: insertedRows, withAnimation: shouldAnimate ? [NSTableView.AnimationOptions.slideDown] : [])
        }
        serverListTableView.endUpdates()
    }

}

extension CountriesSectionViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return viewModel.cellCount
    }
}

extension CountriesSectionViewController: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch viewModel.cellModel(forRow: row) {
        case .country:
            return 48
        case .header:
            return 32
        default:
            return 40
        }
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let cellWrapper = viewModel.cellModel(forRow: row) else {
            PMLog.D("Countries section failed to load cell for row \(row).", level: .error)
            return nil
        }
        
        switch cellWrapper {
        case .country(let model):
            let cell = tableView.makeView(withIdentifier: Cell.country.identifier, owner: self) as! CountryItemCellView
            cell.disabled = quickSettingDetailDisplayed
            cell.updateView(withModel: model)
            return cell
        case .server(let model):
            let cell = tableView.makeView(withIdentifier: Cell.server.identifier, owner: self) as! ServerItemCellView
            cell.disabled = quickSettingDetailDisplayed
            cell.updateView(withModel: model)
            cell.delegate = self
            return cell
        case .header(let model):
            let cell = tableView.makeView(withIdentifier: Cell.header.identifier, owner: self) as! CountriesSectionHeaderView
            cell.viewModel = model
            return cell
        }
    }
}

extension CountriesSectionViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        clearSearchBtn.isHidden = searchTextField.stringValue.isEmpty
        viewModel.filterContent(forQuery: searchTextField.stringValue)
    }
}

extension CountriesSectionViewController: CountriesSettingsDelegate {
    func updateQuickSettings(secureCore: Bool, netshield: NetShieldType, killSwitch: Bool) {
        secureCoreBtn.switchState(secureCore ? #imageLiteral(resourceName: "qs_securecore_on") : #imageLiteral(resourceName: "qs_securecore_off"), enabled: secureCore)
        killSwitchBtn.switchState(killSwitch ? #imageLiteral(resourceName: "qs_killswitch_on") : #imageLiteral(resourceName: "qs_killswitch_off"), enabled: killSwitch)
        netShieldBtn.switchState(netshield == .off ? #imageLiteral(resourceName: "qs_netshield_off") : ( netshield == .level1 ? #imageLiteral(resourceName: "qs_netshield_level1") : #imageLiteral(resourceName: "qs_netshield_level2") ), enabled: netshield != .off)
        children
            .compactMap { $0 as? QuickSettingsDetailViewControllerProtocol }
            .forEach { $0.reloadOptions() }
    }
}

extension CountriesSectionViewController: ServerItemCellViewDelegate {
    func userDidRequestServerInfo(for cell: NSView, server: ServerItemViewModel) {
        showInfo(for: serverListTableView.row(for: cell), and: cell, with: server.serverModel)
    }

    func userDidRequestStreamingInfo(server: ServerItemViewModel) {
        viewModel.showStreamingServices(server: server)
    }
}
