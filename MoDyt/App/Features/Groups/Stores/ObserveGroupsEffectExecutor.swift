import Foundation

struct ObserveGroupsEffectExecutor: Sendable {
    let observeGroups: @Sendable () async -> any AsyncSequence<[Group], Never> & Sendable

    @concurrent
    func callAsFunction() async -> AsyncStream<GroupsEvent> {
        let stream = await observeGroups()
        return makeEventStream(from: stream) { groups in
            .groupsObserved(groups)
        }
    }
}
