import Foundation

// ADR-050 050-D save-outcome classification (classification rules accepted 2026-10-02). Pure: it compares
// caller-supplied observations with prior / intended snapshots and returns a domain outcome. It performs
// no reads, no filesystem work and no cleanup, and it cannot know whether the caller's read was independent
// of context / coordinator caches (OD-10's dedicated-context policy is implemented separately by
// `SwiftDataProjectRepository.observePersistedState(for:)`; it is a policy, not a cache-bypass guarantee).

/// A complete, order-aware comparison value for one persisted Project. Active Clips compare in timeline
/// order with every field; pending-deleted Clips compare as a set keyed by identity (with every field,
/// deletion record included), so fetch order never matters.
struct ProjectStateSnapshot: Equatable, Sendable {
    let id: UUID
    let orientation: ProjectOrientation
    let createdAt: Date
    let updatedAt: Date
    let activeClips: [VlogClip]
    let pendingDeletedClips: [UUID: VlogClip]
    /// Every Clip (active and pending-deleted) belongs to `id` and no identity repeats. `VlogProject.init`
    /// already rejects foreign or duplicate Clip identities, so this is always true for values built
    /// through the domain; it is kept as a defensive part of the comparison, not as an extra check.
    let ownershipIsConsistent: Bool

    init(_ project: VlogProject) {
        id = project.id
        orientation = project.orientation
        createdAt = project.createdAt
        updatedAt = project.updatedAt
        activeClips = project.clips
        let durable = project.durableClips
        pendingDeletedClips = Dictionary(project.deletedClips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        ownershipIsConsistent = durable.allSatisfy { $0.projectID == project.id }
            && Set(durable.map(\.id)).count == durable.count
    }

    var clipIDs: Set<UUID> { Set(activeClips.map(\.id)).union(pendingDeletedClips.keys) }
}

/// The state one Project ID is expected to have.
enum ExpectedProjectState: Equatable, Sendable {
    /// Verified absent (for example a Project the operation creates or deletes) — not "unknown".
    case absent
    case present(ProjectStateSnapshot)
}

enum ProjectSaveExpectationError: Error, Equatable, Sendable {
    /// `update` was given two different Project identities.
    case mismatchedProjectIDs
    /// `replace` was given the same Project identity for A and B.
    case sameProjectID
    /// `replace` was given a B that reuses one of A's Clip identities.
    case overlappingClipIdentities
}

/// What a save is meant to change: the prior and intended states of every Project it touches, and the
/// identities the operation creates (new Project IDs and new Clip IDs with their intended owner). Only the
/// validated factories below can build one.
struct ProjectSaveExpectation: Equatable, Sendable {
    let prior: [UUID: ExpectedProjectState]
    let intended: [UUID: ExpectedProjectState]
    let createdProjectIDs: Set<UUID>
    /// New Clip ID → the Project that should own it once the save is durable.
    let createdClipOwners: [UUID: UUID]

    private init(prior: [UUID: ExpectedProjectState], intended: [UUID: ExpectedProjectState], createdProjectIDs: Set<UUID>, createdClipOwners: [UUID: UUID]) {
        self.prior = prior
        self.intended = intended
        self.createdProjectIDs = createdProjectIDs
        self.createdClipOwners = createdClipOwners
    }

    #if DEBUG
    /// Test seam: builds an expectation WITHOUT validation, to prove the classifier's structural guard.
    /// Absent from Release; production code must use the factories.
    static func debugUnvalidated(prior: [UUID: ExpectedProjectState], intended: [UUID: ExpectedProjectState], createdProjectIDs: Set<UUID> = [], createdClipOwners: [UUID: UUID] = [:]) -> ProjectSaveExpectation {
        ProjectSaveExpectation(prior: prior, intended: intended, createdProjectIDs: createdProjectIDs, createdClipOwners: createdClipOwners)
    }
    #endif

    /// Select Clips new Project: B absent → B present.
    static func create(_ project: VlogProject) -> ProjectSaveExpectation {
        ProjectSaveExpectation(
            prior: [project.id: .absent],
            intended: [project.id: .present(ProjectStateSnapshot(project))],
            createdProjectIDs: [project.id],
            createdClipOwners: Dictionary(uniqueKeysWithValues: project.durableClips.map { ($0.id, project.id) })
        )
    }

    /// Single-save saved-Project replacement (ADR-033 Revision 1): A present + B absent → A absent + B present.
    static func replace(_ previous: VlogProject, with project: VlogProject) throws(ProjectSaveExpectationError) -> ProjectSaveExpectation {
        guard previous.id != project.id else { throw .sameProjectID }
        let previousClipIDs = Set(previous.durableClips.map(\.id))
        guard project.durableClips.allSatisfy({ !previousClipIDs.contains($0.id) }) else { throw .overlappingClipIdentities }
        return ProjectSaveExpectation(
            prior: [previous.id: .present(ProjectStateSnapshot(previous)), project.id: .absent],
            intended: [previous.id: .absent, project.id: .present(ProjectStateSnapshot(project))],
            createdProjectIDs: [project.id],
            createdClipOwners: Dictionary(uniqueKeysWithValues: project.durableClips.map { ($0.id, project.id) })
        )
    }

    /// Editor Add / Replace (whole-Project `update`): before → after; the created Clips are the identities
    /// present after but not before.
    static func update(from before: VlogProject, to after: VlogProject) throws(ProjectSaveExpectationError) -> ProjectSaveExpectation {
        guard before.id == after.id else { throw .mismatchedProjectIDs }
        let existing = Set(before.durableClips.map(\.id))
        return ProjectSaveExpectation(
            prior: [before.id: .present(ProjectStateSnapshot(before))],
            intended: [after.id: .present(ProjectStateSnapshot(after))],
            createdProjectIDs: [],
            createdClipOwners: Dictionary(uniqueKeysWithValues: after.durableClips.filter { !existing.contains($0.id) }.map { ($0.id, after.id) })
        )
    }

    /// Prior and intended cannot be told apart (same Project IDs, equal states).
    var isIndistinguishable: Bool { prior == intended }

    /// Defensive structural check: both sides non-empty, covering the same Project IDs, and every created
    /// identity tied to a Project the intended state expects to be present.
    var isStructurallyValid: Bool {
        guard !prior.isEmpty, Set(prior.keys) == Set(intended.keys) else { return false }
        func present(_ id: UUID) -> Bool { if case .present? = intended[id] { return true } else { return false } }
        return createdProjectIDs.allSatisfy(present) && createdClipOwners.values.allSatisfy(present)
    }
}

/// One Project ID as the caller's read reported it.
enum ObservedProjectRecord: Equatable, Sendable {
    /// The read succeeded and found no row with this ID.
    case absent
    case present(VlogProject)
    /// The read failed or the row could not be converted to a domain value.
    case unreadable
}

/// The caller's report of persisted state after a save attempt. These are caller-supplied observations,
/// not proof of a cache-independent durable read.
struct PersistedStateObservation: Equatable, Sendable {
    /// Every Project ID in the expectation should appear here; a missing entry counts as not observed.
    let projects: [UUID: ObservedProjectRecord]
    /// Store-wide result of looking up the operation-created identities, or nil when no lookup result is
    /// available at all. For each queried identity: the Project IDs that hold it (a Project ID "holds" itself
    /// when its row exists; a Clip ID is held by the Project that owns the row). Empty set = absent. A created
    /// identity with no key (for example its query batch failed) counts as not observed.
    let createdIdentityHolders: [UUID: Set<UUID>]?
}

enum ProjectSaveAttempt: Equatable, Sendable {
    case succeeded
    case threw
}

enum ProjectSaveOutcome: Equatable, Sendable {
    /// The intended state is confirmed.
    case completed
    /// The save reported success but the intended state was not confirmed. Potentially referenced media
    /// must be preserved and rollback is never authorized.
    case committedUnverified(ProjectSaveOutcomeReason)
    /// The save threw and the prior state is confirmed, including store-wide absence of every created
    /// identity: eligible for pre-commit rollback.
    case priorConfirmed
    /// The save threw and nothing could be confirmed. Potentially referenced media must be preserved and
    /// Retry is prohibited.
    case indeterminate(ProjectSaveOutcomeReason)
}

enum ProjectSaveOutcomeReason: Equatable, Sendable {
    /// A required Project ID was not part of the observation.
    case notObserved
    /// A required Project read failed.
    case unreadable
    /// Some Projects match the prior state and others the intended state.
    case partial
    /// The observation matches neither the prior nor the intended state (field, order, ownership, row).
    case contradictory
    /// Prior and intended states are identical, so the observation cannot tell them apart.
    case indistinguishable
    /// The expectation is empty or structurally invalid.
    case invalidExpectation
    /// The store-wide created-identity lookup is missing or incomplete.
    case identityEvidenceMissing
    /// A created identity was found in the store (in any Project) while the prior state was observed.
    case createdIdentityPresent
}

enum ProjectSaveOutcomeClassifier {
    static func classify(_ attempt: ProjectSaveAttempt, expectation: ProjectSaveExpectation, observation: PersistedStateObservation) -> ProjectSaveOutcome {
        guard expectation.isStructurallyValid else {
            return attempt == .succeeded ? .committedUnverified(.invalidExpectation) : .indeterminate(.invalidExpectation)
        }
        let intended = match(expectation.intended, observation)
        switch attempt {
        case .succeeded:
            // A successful save never authorizes rollback, whatever the observation looks like. Completion
            // here only needs the intended state and no contradicting identity evidence.
            if intended == .matches, createdIdentitiesHeldAsIntended(expectation, observation) != .some(false) { return .completed }
            return .committedUnverified(reason(expectation, observation, intended: intended))
        case .threw:
            if expectation.isIndistinguishable { return .indeterminate(.indistinguishable) }
            if intended == .matches {
                // After a throw, completion also needs complete store-wide evidence that every created
                // identity is held exactly as intended (vacuous when nothing is created).
                switch createdIdentitiesHeldAsIntended(expectation, observation) {
                case .some(true): return .completed
                case .some(false): return .indeterminate(.contradictory)
                case .none: return .indeterminate(.identityEvidenceMissing)
                }
            }
            guard match(expectation.prior, observation) == .matches else {
                return .indeterminate(reason(expectation, observation, intended: intended))
            }
            switch createdIdentitiesAbsent(expectation, observation) {
            case .some(true): return .priorConfirmed
            case .some(false): return .indeterminate(.createdIdentityPresent)
            case .none: return .indeterminate(.identityEvidenceMissing)
            }
        }
    }

    // MARK: Comparison

    private enum Match: Equatable { case matches, notObserved, unreadable, differs }

    private static func match(_ expected: [UUID: ExpectedProjectState], _ observation: PersistedStateObservation) -> Match {
        var result = Match.matches
        for (id, state) in expected {
            let one: Match
            switch (state, observation.projects[id]) {
            case (_, nil): one = .notObserved
            case (_, .unreadable?): one = .unreadable
            case (.absent, .absent?): one = .matches
            case (.present(let snapshot), .present(let project)?):
                let observed = ProjectStateSnapshot(project)
                one = observed.ownershipIsConsistent && observed == snapshot ? .matches : .differs
            default: one = .differs
            }
            result = worse(result, one)
        }
        return result
    }

    private static func worse(_ a: Match, _ b: Match) -> Match {
        let rank: [Match: Int] = [.matches: 0, .differs: 1, .notObserved: 2, .unreadable: 3]
        return rank[a, default: 0] >= rank[b, default: 0] ? a : b
    }

    private static func reason(_ expectation: ProjectSaveExpectation, _ observation: PersistedStateObservation, intended: Match) -> ProjectSaveOutcomeReason {
        let prior = match(expectation.prior, observation)
        if intended == .unreadable || prior == .unreadable { return .unreadable }
        if intended == .notObserved || prior == .notObserved { return .notObserved }
        if intended == .matches || prior == .matches { return .contradictory }
        // Per Project: some IDs at their prior state and others at their intended state.
        let ids = Set(expectation.prior.keys).union(expectation.intended.keys)
        var priorHits = 0, intendedHits = 0
        for id in ids {
            if let state = expectation.prior[id], match([id: state], observation) == .matches { priorHits += 1 }
            if let state = expectation.intended[id], match([id: state], observation) == .matches { intendedHits += 1 }
        }
        return priorHits > 0 && intendedHits > 0 ? .partial : .contradictory
    }

    /// true: every created identity is held exactly by its intended holder (a Project by itself, a Clip by
    /// its intended owner) and nowhere else. false: evidence places one elsewhere or nowhere. nil: the lookup
    /// is missing or does not cover every created identity. Vacuously true when nothing is created.
    private static func createdIdentitiesHeldAsIntended(_ expectation: ProjectSaveExpectation, _ observation: PersistedStateObservation) -> Bool? {
        var expected: [UUID: Set<UUID>] = [:]
        for projectID in expectation.createdProjectIDs { expected[projectID] = [projectID] }
        for (clipID, owner) in expectation.createdClipOwners { expected[clipID] = [owner] }
        if expected.isEmpty { return true }
        guard let holders = observation.createdIdentityHolders else { return nil }
        // Scan every key: a contradiction anywhere wins over a missing key, independent of iteration order.
        var contradicted = false, missing = false
        for (id, wanted) in expected {
            if let found = holders[id] { if found != wanted { contradicted = true } } else { missing = true }
        }
        if contradicted { return false }
        return missing ? nil : true
    }

    /// true: every created identity was looked up store-wide and found nowhere. false: at least one was
    /// found. nil: the lookup is missing or does not cover every created identity. Vacuously true when
    /// nothing is created.
    private static func createdIdentitiesAbsent(_ expectation: ProjectSaveExpectation, _ observation: PersistedStateObservation) -> Bool? {
        let required = expectation.createdProjectIDs.union(expectation.createdClipOwners.keys)
        if required.isEmpty { return true }
        guard let holders = observation.createdIdentityHolders else { return nil }
        // Scan every key: a found identity wins over a missing key, independent of iteration order.
        var anyPresent = false, missing = false
        for id in required {
            if let found = holders[id] { if !found.isEmpty { anyPresent = true } } else { missing = true }
        }
        if anyPresent { return false }
        return missing ? nil : true
    }
}
