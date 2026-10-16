.pragma library

// Isolate displayed values, not their underlying identities or link targets.
// Replace template placeholders once so a value containing %2 stays intact.
function format(template, args, rtl) {
    return template.replace(/%([1-9][0-9]*)/g, function(match, number) {
        const value = args[Number(number) - 1]
        if (value === undefined) return match
        return rtl ? "\u2068" + String(value) + "\u2069" : String(value)
    })
}
