//
//  MakeRectWithAspectRatio.swift
//  drift
//
//  Created by Jonny Kuang on 1/8/20.
//  Copyright © 2020 Jonny Kuang. All rights reserved.
//

import CoreGraphics

public func KJYMakeRect(withAspectRatio aspectRatio: CGSize, fitRect boundingRect: CGRect, roundsValues: Bool = true) -> CGRect {
    _KJYMakeRect(withAspectRatio: aspectRatio, boundingRect: boundingRect, fit: true, roundsValues: roundsValues)
}

public func KJYMakeRect(withAspectRatio aspectRatio: CGSize, fillRect boundingRect: CGRect, roundsValues: Bool = true) -> CGRect {
    _KJYMakeRect(withAspectRatio: aspectRatio, boundingRect: boundingRect, fit: false, roundsValues: roundsValues)
}

private func _KJYMakeRect(withAspectRatio aspectRatio: CGSize, boundingRect: CGRect, fit: Bool, roundsValues: Bool) -> CGRect {
    
    let boundingRatio = boundingRect.width / boundingRect.height
    let contentRatio = aspectRatio.width / aspectRatio.height
    var rect: CGRect
    
    if (boundingRatio - contentRatio) * CGFloat(fit ? 1 : -1) > 0 {
        let height = boundingRect.height
        let width = height * contentRatio
        rect = CGRect(x: boundingRect.origin.x + (boundingRect.width - width) / 2, y: boundingRect.origin.y, width: width, height: height)
    } else {
        let width = boundingRect.width
        let height = width / contentRatio
        rect = CGRect(x: boundingRect.origin.x, y: boundingRect.origin.y + (boundingRect.height - height) / 2, width: width, height: height)
    }
    if roundsValues {
        rect.origin.x = round(rect.origin.x)
        rect.origin.y = round(rect.origin.y)
        rect.size.width = round(rect.width)
        rect.size.height = round(rect.height)
    }
    return rect
}
