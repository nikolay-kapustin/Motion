/*
 * The MIT License (MIT)
 *
 * Copyright (C) 2017, Daniel Dahan and CosmicMind, Inc. <http://cosmicmind.com>.
 * All rights reserved.
 *
 * Original Inspiration & Author
 * Copyright (c) 2016 Luke Zhao <me@lkzhao.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import UIKit

#if os(iOS)
public class MotionDebugPlugin: MotionPlugin {
  public static var showOnTop: Bool = false

  var debugView: MotionDebugView?
  var zPositionMap = [UIView: CGFloat]()
  var addedLayers: [CALayer] = []
  var updating = false

  override public func animate(fromViews: [UIView], toViews: [UIView]) -> TimeInterval {
    if Motion.shared.forceNonInteractive { return 0 }
    var hasArc = false
    for v in context.fromViews + context.toViews where context[v]?.arc != nil && context[v]?.position != nil {
      hasArc = true
      break
    }
    let debugView = MotionDebugView(initialProcess: Motion.shared.isPresenting ? 0.0 : 1.0, showCurveButton:hasArc, showOnTop:MotionDebugPlugin.showOnTop)
    debugView.frame = Motion.shared.container.bounds
    debugView.delegate = self
    UIApplication.shared.keyWindow!.addSubview(debugView)

    debugView.layoutSubviews()
    self.debugView = debugView

    UIView.animate(withDuration: 0.4) {
      debugView.showControls = true
    }

    return .infinity
  }

  public override func resume(at: TimeInterval, isReversed: Bool) -> TimeInterval {
    guard let debugView = debugView else { return 0.4 }
    debugView.delegate = nil

    UIView.animate(withDuration: 0.4) {
      debugView.showControls = false
      debugView.debugSlider.setValue(roundf(debugView.progress), animated: true)
    }

    on3D(wants3D: false)
    return 0.4
  }

  public override func clean() {
    debugView?.removeFromSuperview()
    debugView = nil
  }
}

extension MotionDebugPlugin:MotionDebugViewDelegate {
  public func onDone() {
    guard let debugView = debugView else { return }
    let seekValue = Motion.shared.isPresenting ? debugView.progress : 1.0 - debugView.progress
    if seekValue > 0.5 {
      Motion.shared.end()
    } else {
      Motion.shared.cancel()
    }
  }

  public func onProcessSliderChanged(progress: Float) {
    let seekValue = Motion.shared.isPresenting ? progress : 1.0 - progress
    Motion.shared.update(elapsedTime: Double(seekValue))
  }

  func onPerspectiveChanged(translation: CGPoint, rotate: CGFloat, scale: CGFloat) {
    var t = CATransform3DIdentity
    t.m34 = -1 / 4000
    t = CATransform3DTranslate(t, translation.x, translation.y, 0)
    t = CATransform3DScale(t, scale, scale, 1)
    t = CATransform3DRotate(t, rotate, 0, 1, 0)
    Motion.shared.container.layer.sublayerTransform = t
  }

  func animateZPosition(view: UIView, to: CGFloat) {
    let a = CABasicAnimation(keyPath: "zPosition")
    a.fromValue = view.layer.value(forKeyPath: "zPosition")
    a.toValue = NSNumber(value: Double(to))
    a.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
    a.duration = 0.4
    view.layer.add(a, forKey: "zPosition")
    view.layer.zPosition = to
  }

  func onDisplayArcCurve(wantsCurve: Bool) {
    for layer in addedLayers {
      layer.removeFromSuperlayer()
      addedLayers.removeAll()
    }
    if wantsCurve {
      for layer in Motion.shared.container.layer.sublayers! {
        for (_, anim) in layer.animations {
          if let keyframeAnim = anim as? CAKeyframeAnimation, let path = keyframeAnim.path {
            let s = CAShapeLayer()
            s.zPosition = layer.zPosition + 10
            s.path = path
            s.strokeColor = UIColor.blue.cgColor
            s.fillColor = UIColor.clear.cgColor
            Motion.shared.container.layer.addSublayer(s)
            addedLayers.append(s)
          }
        }
      }
    }
  }

  func on3D(wants3D: Bool) {
    var t = CATransform3DIdentity
    if wants3D {
      var viewsWithZPosition = Set<UIView>()
      for view in Motion.shared.container.subviews where view.layer.zPosition != 0 {
        viewsWithZPosition.insert(view)
        zPositionMap[view] = view.layer.zPosition
      }

      let viewsWithoutZPosition = Motion.shared.container.subviews.filter { return !viewsWithZPosition.contains($0) }
      let viewsWithPositiveZPosition = viewsWithZPosition.filter { return $0.layer.zPosition > 0 }

      for (i, v) in viewsWithoutZPosition.enumerated() {
        animateZPosition(view:v, to:CGFloat(i * 10))
      }

      var maxZPosition: CGFloat = 0
      for v in viewsWithPositiveZPosition {
        maxZPosition = max(maxZPosition, v.layer.zPosition)
        animateZPosition(view:v, to:v.layer.zPosition + CGFloat(viewsWithoutZPosition.count * 10))
      }

      t.m34 = -1 / 4000
      t = CATransform3DTranslate(t, debugView!.translation.x, debugView!.translation.y, 0)
      t = CATransform3DScale(t, debugView!.scale, debugView!.scale, 1)
      t = CATransform3DRotate(t, debugView!.rotate, 0, 1, 0)
    } else {
      for v in Motion.shared.container.subviews {
        animateZPosition(view:v, to:self.zPositionMap[v] ?? 0)
      }
      self.zPositionMap.removeAll()
    }

    let a = CABasicAnimation(keyPath: "sublayerTransform")
    a.fromValue = Motion.shared.container.layer.value(forKeyPath: "sublayerTransform")
    a.toValue = NSValue(caTransform3D: t)
    a.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
    a.duration = 0.4

    UIView.animate(withDuration:0.4) {
      self.context.container.backgroundColor = UIColor(white: 0.85, alpha: 1.0)
    }

    Motion.shared.container.layer.add(a, forKey: "debug")
    Motion.shared.container.layer.sublayerTransform = t
  }
}
#endif
