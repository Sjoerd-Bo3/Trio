/// Tracks where a bolus is in its lifecycle, derived from the pump's `bolusState`.
///
/// - `noBolus`: nothing is being delivered.
/// - `initiating`: the app has asked the pump to bolus, but delivery has not yet
///   started (no progress to report yet).
/// - `inProgress`: the pump is actively delivering and reporting progress.
enum BolusStatus {
    case noBolus
    case initiating
    case inProgress
}
