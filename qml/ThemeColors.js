.pragma library

function luminance(color) {
    function linear(value) {
        return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
}

function contrast(foreground, background) {
    const a = luminance(foreground), b = luminance(background)
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
}

function readableText(color, backgrounds, foreground) {
    function readable(candidate) {
        return backgrounds.every(function(background) { return contrast(candidate, background) >= 4.55 })
    }
    if (readable(color)) return color
    // Preserve the KDE link/accent hue, adjusting only when a preset (notably
    // yellow on a light surface) is too faint for small publisher/link text.
    let low = 0, high = 1
    for (let step = 0; step < 12; ++step) {
        const amount = (low + high) / 2
        const candidate = Qt.tint(color, Qt.rgba(foreground.r, foreground.g, foreground.b, amount))
        if (readable(candidate)) high = amount
        else low = amount
    }
    // Normalize the adjusted result to a regular RGB color so Controls and
    // Qt Quick labels receive the same value (not different float formats).
    return Qt.tint(color, Qt.rgba(foreground.r, foreground.g, foreground.b, high)).toString()
}
