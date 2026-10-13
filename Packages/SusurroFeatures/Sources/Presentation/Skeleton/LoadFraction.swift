extension Double {
    /// A load progress as a fraction from 0 to 1. A value that is not a number, or is infinite, counts as no progress:
    /// whoever shows it as a percentage would otherwise trap on the conversion to an integer.
    var loadFraction: Double {
        isFinite ? min(max(self, 0), 1) : 0
    }
}
