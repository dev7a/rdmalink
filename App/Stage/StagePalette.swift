//
//  StagePalette.swift
//
//  The only place the stage decides what anything is made of.
//
//  UX_SPEC §4.1: "Only three tones are ever used on the model: `.secondary`,
//  `accent`, and the unlit recess." Nothing in the scene carries meaning in
//  hue — every state is a ring geometry — so the palette's whole job is to
//  keep the machine legible in both appearances and under Increase Contrast.
//

import AppKit
import RealityKit
import SwiftUI

/// The accessibility and appearance settings the scene reads. One value, so a
/// change is one comparison and one rebuild.
struct StageAppearance: Equatable, Sendable {
    var colorScheme: ColorScheme = .light
    var reduceMotion = false
    var increaseContrast = false
    var reduceTransparency = false

    var isDark: Bool { colorScheme == .dark }

    /// §3.6: every ring track goes from 1.5 pt to 3 pt under Increase Contrast.
    /// On the model that is a thickness in centimetres, sized so it reads at
    /// about 1.5 pt at the resting distance; the doubling is exact.
    var ringScale: Double { increaseContrast ? 2 : 1 }
}

/// Resolved colours for one appearance.
@MainActor
struct StagePalette {
    let appearance: StageAppearance

    /// §3.4: the aluminium's own silver, 0.78 luminance, in **both**
    /// appearances. "There is no dark Mac Studio or Mac mini, and macOS does
    /// not report a MacBook Pro's finish, so silver is the honest default
    /// everywhere: dark mode changes the light, never the metal." The light
    /// is the dimmer IBL and the rim in `StageSceneBuilder.makeLights`.
    var chassis: NSColor { grey(0.78) }

    /// §3.4: receptacles read as holes, so the interior is the darkest thing
    /// in the scene in both appearances.
    var recess: NSColor { grey(appearance.isDark ? 0.045 : 0.08) }

    /// §4.5: USB-only receptacles use a matte, non-reflective interior so they
    /// look different before anyone explains why.
    var usbRecess: NSColor { grey(appearance.isDark ? 0.075 : 0.11) }

    /// §4.2: a plug stub in a matte grey that deliberately does not match the
    /// chassis, so it reads as foreign.
    var stub: NSColor { grey(appearance.isDark ? 0.42 : 0.49) }

    /// §3.4's "soft inset" at the base: a shadow line under the body, not a
    /// second, darker object. It sits between the chassis and a recess, and
    /// it is a shadow rather than metal, so it is the one tone on the shell
    /// that still follows the appearance: under the dark IBL the silver
    /// body renders at 35–55 of 255 against a 30 background, and a band
    /// lighter than 0.12 would vanish between the two.
    var baseInset: NSColor { grey(appearance.isDark ? 0.12 : 0.42) }

    var keyboard: NSColor { grey(0.10) }
    var screen: NSColor { grey(0.045) }
    var scenery: NSColor { grey(appearance.isDark ? 0.10 : 0.17) }
    var indicator: NSColor { grey(0.96) }

    /// The `.secondary` tone on the model: ink that contrasts with the chassis
    /// rather than a colour that means something.
    ///
    /// §3.4: the metal is the same silver in both appearances, so the ink
    /// follows the **light**, not the base colour. Under the dark IBL a
    /// 0.78 chassis renders dark where the rings sit — measured 2026-09-20
    /// through the corrected capture (App/Stage/StageSnapshot.swift): 35–41
    /// of 255 along the Mac Studio's back port row, 87 along the front row,
    /// against 169–175 in light mode — which is why the ink is near-white in
    /// dark mode and near-black in light, and why swapping either would lose
    /// the rings.
    var ink: NSColor { grey(appearance.isDark ? 0.96 : 0.11) }

    /// §4.4: the bridge ribbon is the same `.secondary` ink — "tone and
    /// geometry, never a color channel" — and a bridge that is **not in use**
    /// takes "a marginally cooler value" of it, which is the one place the
    /// stage bends a tone rather than a shape, and the spec asks for it by
    /// name. The 8 % blend is a value, not a hue: at a sixteenth of the
    /// ribbon's own opacity it never reads as blue, only as further away.
    var ribbonInactiveInk: NSColor {
        let cool = NSColor(srgbRed: 0.62, green: 0.70, blue: 0.86, alpha: 1)
        return ink.blended(withFraction: 0.08, of: cool)?.usingColorSpace(.sRGB) ?? ink
    }

    /// §3.4: in dark mode the accent ring brightens one step to hold contrast.
    var accent: NSColor {
        let resolved = resolve(.controlAccentColor)
        guard appearance.isDark else { return resolved }
        let brighter = resolved.blended(withFraction: 0.18, of: .white)
        return brighter?.usingColorSpace(.sRGB) ?? resolved
    }

    /// §3.4: the stage background is `.windowBackground` in both appearances.
    var background: NSColor { resolve(.windowBackgroundColor) }

    /// §3.4: a very shallow radial lift behind the chassis.
    ///
    /// The "dark mode is unreadable" measurement that used to be recorded here
    /// was an artefact of the review capture, which wrote the renderer's linear
    /// buffer into eight bits without encoding it — see the note in
    /// App/Stage/StageSnapshot.swift. Nothing is claimed about the lighting
    /// here until it has been measured again through a corrected capture.
    var backgroundLift: NSColor {
        let base = background
        let target: NSColor = appearance.isDark ? .white : .black
        let lifted = base.blended(withFraction: appearance.isDark ? 0.055 : 0.035, of: target)
        return lifted?.usingColorSpace(.sRGB) ?? base
    }

    // MARK: - Materials

    var chassisMaterial: PhysicallyBasedMaterial {
        surface(chassis, roughness: 0.38, metallic: 0.85)
    }

    var recessMaterial: PhysicallyBasedMaterial {
        surface(recess, roughness: 0.9, metallic: 0.1)
    }

    var usbRecessMaterial: PhysicallyBasedMaterial {
        surface(usbRecess, roughness: 1.0, metallic: 0.0)
    }

    var stubMaterial: PhysicallyBasedMaterial {
        surface(stub, roughness: 0.6, metallic: 0.2)
    }

    var baseInsetMaterial: PhysicallyBasedMaterial {
        surface(baseInset, roughness: 0.7, metallic: 0.5)
    }

    var sceneryMaterial: PhysicallyBasedMaterial {
        surface(scenery, roughness: 0.85, metallic: 0.15)
    }

    var keyboardMaterial: PhysicallyBasedMaterial {
        surface(keyboard, roughness: 0.95, metallic: 0.0)
    }

    var screenMaterial: PhysicallyBasedMaterial {
        surface(screen, roughness: 0.25, metallic: 0.1)
    }

    /// The Mac Studio's back grille: `StageMesh.grille()`'s tile read as an
    /// opacity mask over the recess tone, so each hole is the same darkness
    /// as the inside of a receptacle — a hole is a recess. The threshold is
    /// the prototype's `alphaTest: 0.2`; it makes the material a cut-out that
    /// writes depth like an opaque surface, so the aluminium and its sheen
    /// show between the holes and every ring above it wins the depth test.
    func grilleMaterial(texture: TextureResource) -> PhysicallyBasedMaterial {
        var material = surface(recess, roughness: 0.9, metallic: 0.0)
        material.blending = .transparent(
            opacity: .init(texture: .init(texture, sampler: StageMesh.grilleSampler()))
        )
        material.opacityThreshold = 0.2
        return material
    }

    var indicatorMaterial: UnlitMaterial { flat(indicator) }

    var inkMaterial: UnlitMaterial { flat(ink) }

    var accentMaterial: UnlitMaterial { flat(accent) }

    /// §4.4's ribbon. The opacity is the scene's — one number on the link, so
    /// an inactive bridge's 40 % and the cross-fade are the same control.
    func ribbonMaterial(active: Bool) -> UnlitMaterial {
        flat(active ? ink : ribbonInactiveInk)
    }

    /// §4.2's light thread: the ink, faded along the tube by `fade`, which
    /// `StageMesh.threadFade()` draws as the thread's opacity against the
    /// sweep's own `u`. The fade has to be in the material because it runs
    /// *along one mesh* — the spec's "never a chain of visible segments"
    /// rules out the alternative of one material per piece. The cross-fade
    /// on and off stays an `OpacityComponent` above it, as everywhere else.
    func threadMaterial(fade: TextureResource) -> UnlitMaterial {
        var material = inkMaterial
        material.blending = .transparent(opacity: .init(texture: .init(fade)))
        return material
    }

    // MARK: - Private

    private func surface(
        _ color: NSColor, roughness: Float, metallic: Float
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: metallic)
        return material
    }

    /// Ring tracks are unlit so a state never reads differently because of
    /// where the key light happens to be. Opacity lives in an
    /// `OpacityComponent` so a cross-fade is one number, not a new material.
    private func flat(_ color: NSColor) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: 1.0)
        material.faceCulling = .none
        return material
    }

    private func grey(_ value: CGFloat) -> NSColor {
        NSColor(srgbRed: value, green: value, blue: value, alpha: 1)
    }

    /// Dynamic system colours resolve against whatever appearance is current,
    /// which in a `RealityView` build closure is not necessarily the window's.
    private func resolve(_ color: NSColor) -> NSColor {
        let name: NSAppearance.Name = appearance.isDark ? .darkAqua : .aqua
        guard let target = NSAppearance(named: name) else {
            return color.usingColorSpace(.sRGB) ?? color
        }
        var resolved = color
        target.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }
}
