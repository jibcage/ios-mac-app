//
//  FeatureTableViewCell.swift
//  ProtonVPN - Created on 21.04.21.
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

import UIKit
import vpncore

class FeatureTableViewCell: UITableViewCell {
    
    @IBOutlet private weak var iconIV: UIImageView!
    @IBOutlet private weak var titleLbl: UILabel!
    @IBOutlet private weak var descriptionLbl: UILabel!
    @IBOutlet private weak var learnMoreBtn: UIButton!
    
    @IBOutlet weak var loadViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet private weak var loadView: UIView!
    @IBOutlet private weak var loadLowView: UIView!
    @IBOutlet private weak var loadLowLbl: UILabel!
    @IBOutlet private weak var loadMediumView: UIView!
    @IBOutlet private weak var loadMediumLbl: UILabel!
    @IBOutlet private weak var loadHighView: UIView!
    @IBOutlet private weak var loadHighLbl: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        selectionStyle = .none
        backgroundColor = .protonWidgetBackground
    }
    
    var viewModel: FeatureCellViewModel! {
        didSet {
            titleLbl.text = viewModel.title
            iconIV.image = UIImage(named: viewModel.icon)
            descriptionLbl.text = viewModel.description
            learnMoreBtn.setTitle(LocalizedString.learnMore, for: .normal)
            
            if viewModel.displayLoads {
                loadView.isHidden = false
                loadViewHeightConstraint.constant = 32
                loadLowLbl.text = LocalizedString.performanceLoadLow
                loadLowView.backgroundColor = .protonGreen()
                loadMediumLbl.text = LocalizedString.performanceLoadMedium
                loadMediumView.backgroundColor = .protonYellow()
                loadHighLbl.text = LocalizedString.performanceLoadHigh
                loadHighView.backgroundColor = .protonRed()
            } else {
                loadView.isHidden = true
                loadViewHeightConstraint.constant = 0
            }
        }
    }
    
    // MARK: - Actions
    
    @IBAction private func didTapLearnMore(_ sender: Any) {
        SafariService.openLink(url: viewModel.urlContact)
    }
}
