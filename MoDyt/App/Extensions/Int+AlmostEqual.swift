extension Int {
    func isAlmostEqual(to value: Int, tolerance: Int = 3) -> Bool {
        guard tolerance >= 0 else {
            return false
        }

        let (difference, didOverflow) = subtractingReportingOverflow(value)
        guard didOverflow == false else {
            return false
        }

        return difference.magnitude <= tolerance.magnitude
    }
}

extension Optional where Wrapped == Int {
    func isAlmostEqual(to value: Int, tolerance: Int = 3) -> Bool {
        guard let self else {
            return false
        }

        return self.isAlmostEqual(to: value, tolerance: tolerance)
    }

    func isAlmostEqual(to value: Int?, tolerance: Int = 3) -> Bool {
        switch (self, value) {
        case let (lhs?, rhs?):
            return lhs.isAlmostEqual(to: rhs, tolerance: tolerance)
        case (nil, nil):
            return true
        default:
            return false
        }
    }
}
