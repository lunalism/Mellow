import Foundation

enum RepresentativeThumbnailSource {
    // Usability is supplied by the caller; metadata alone cannot prove media health.
    // Phase 2 displays neutral placeholders and does not read or generate thumbnails.
    static func clipID(in project: VlogProject, isUsable: (VlogClip) -> Bool) -> UUID? {
        project.clips.first(where: isUsable)?.id
    }
}
