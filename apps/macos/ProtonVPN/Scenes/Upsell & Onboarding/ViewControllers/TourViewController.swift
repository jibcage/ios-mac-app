//
//  TourViewController.swift
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

class TourViewController: NSViewController {

    @IBOutlet weak var pageNumberLabel: NSTextField!
    @IBOutlet weak var titleLabel: NSTextField!
    @IBOutlet weak var descriptionLabel: PVPNTextField!
    @IBOutlet weak var previousButton: TourPreviousButton!
    @IBOutlet weak var nextButton: TourNextButton!
    
    private let titles = [
        LocalizedString.quickConnectTourTitle,
        LocalizedString.profilesTourTitle,
        LocalizedString.countriesTourTitle,
        LocalizedString.quickSettingsTourTitle
    ]
    
    private let descriptions = [
        LocalizedString.quickConnectTourDescription,
        LocalizedString.profilesTourDescription,
        LocalizedString.countriesTourDescription,
        LocalizedString.quickSettingsTourDescription
            + "\n• " + LocalizedString.quickSettingsTourFeature1
            + "\n• " + LocalizedString.quickSettingsTourFeature2
            + "\n• " + LocalizedString.quickSettingsTourFeature3
    ]
    
    private let previous: (() -> Void)
    private let next: (() -> Void)
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(previous: @escaping () -> Void, next: @escaping () -> Void) {
        self.previous = previous
        self.next = next
        
        super.init(nibName: NSNib.Name("Tour"), bundle: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        DispatchQueue.main.async { [weak self] in
            self?.display(page: 1)
        }
    }
    
    func display(page: Int) {
        precondition(1...titles.count ~= page)
        
        pageNumberLabel.attributedStringValue = "\(page)".attributed(withColor: .protonWhite(), fontSize: 14)
        
        previousButton.isHidden = page == 1 // hide back button on first page
        nextButton.title = page == titles.count ? LocalizedString.endTour : LocalizedString.nextTip
        nextButton.showArrow = page != titles.count
        
        titleLabel.attributedStringValue = titles[page - 1].attributed(withColor: .protonWhite(), fontSize: 14, alignment: .left)
        descriptionLabel.attributedStringValue = descriptions[page - 1].attributed(withColor: .protonWhite(), fontSize: 12, alignment: .left)
        
        let quickSettingStep = 4
        
        if page == quickSettingStep {
            descriptionLabel.attributedStringValue = descriptionLabel.attributedStringValue.applyStyle(
                for: [LocalizedString.secureCore, LocalizedString.netshieldTitle, LocalizedString.killSwitch],
                attrs: [.font: NSFont.boldSystemFont(ofSize: 12)]
            )
        }
    }
    
    @IBAction func previous(_ sender: Any) {
        previous()
    }
    
    @IBAction func next(_ sender: Any) {
        next()
    }
}
