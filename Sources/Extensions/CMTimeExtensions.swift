import CoreMedia

extension CMTime {
    func clamped(to range: CMTimeRange) -> CMTime {
        if self < range.start { return range.start }
        if self > range.end { return range.end }

        return self
    }
}
