from __future__ import annotations

def signal_key(signal: dict) -> tuple:
    """Identifies a Signal group. Note: this must exactly match `group_dimensions + metric` in your `BlobCreatedEventGridFunction`."""
    return (signal.get("SubAccountId"), signal.get("ServiceName"), signal.get("metric"))

def is_latest_flagged(signal: dict) -> bool:
    """Has the most recent day in this Signal group itself been flagged as an anomaly?
    signal['anomalies'] may also contain older anomalies from previous days that are
    no longer relevant within the same month-to-date export—only "today" counts for the persistence calculation."""
    latest_date = signal.get("latest_date")
    return any(a.get("date") == latest_date for a in signal.get("anomalies", []))

def compute_persistence(
    current_signals: list[dict],
    history_signals_snapshots: list[list[dict]],
) -> dict[tuple, int]:
    """`current_signals`: the `signals` list from `latest.json`.
    `history_signals_snapshots`: a list of earlier `signals` lists (from `history/<timestamp>.json`), ordered
    from most recent to least recent (day -1 first).
    Returns, for each `signal_key()`, the number of consecutive days (including today) on which the most recent
    day in that group was flagged as an anomaly.
    """

    flagged_today = {signal_key(s) for s in current_signals if is_latest_flagged(s)}
    streaks = {k: 1 for k in flagged_today}
    still_counting = set(flagged_today)

    for snapshot_signals in history_signals_snapshots:
        if not still_counting:
            break
        flagged_that_day = {signal_key(s) for s in snapshot_signals if is_latest_flagged(s)}
        for k in list(still_counting):
            if k in flagged_that_day:
                streaks[k] += 1
            else:
                still_counting.discard(k)

    return streaks