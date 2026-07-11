package com.andrew.alarm

import java.util.Calendar
import java.util.TimeZone

/**
 * Weekday-recurrence helpers.
 *
 * The public weekday list uses the ISO 8601 convention (1 = Monday … 7 = Sunday),
 * matching Dart's `DateTime.weekday`. `java.util.Calendar.DAY_OF_WEEK` uses
 * 1 = Sunday … 7 = Saturday, mapped here explicitly.
 */
object WarmAlarmRecurrence {
    /** Converts [Calendar.DAY_OF_WEEK] (1=Sun..7=Sat) to ISO (1=Mon..7=Sun). */
    private fun isoWeekday(calendarDayOfWeek: Int): Int = if (calendarDayOfWeek == Calendar.SUNDAY) 7 else calendarDayOfWeek - 1

    /**
     * Returns the next fire time strictly after [afterMillis] that matches one of
     * [weekdays] (ISO 1=Mon..7=Sun) at the same local time-of-day as [baseMillis],
     * or `null` when [weekdays] is empty.
     */
    fun nextOccurrence(
        baseMillis: Long,
        weekdays: List<Long>,
        afterMillis: Long,
        timeZone: TimeZone = TimeZone.getDefault(),
    ): Long? {
        if (weekdays.isEmpty()) return null
        val isoDays = weekdays.map { it.toInt() }.toSet()

        val base = Calendar.getInstance(timeZone).apply { timeInMillis = baseMillis }
        val candidate =
            Calendar.getInstance(timeZone).apply {
                timeInMillis = afterMillis
                set(Calendar.HOUR_OF_DAY, base.get(Calendar.HOUR_OF_DAY))
                set(Calendar.MINUTE, base.get(Calendar.MINUTE))
                set(Calendar.SECOND, base.get(Calendar.SECOND))
                set(Calendar.MILLISECOND, 0)
            }

        // Scan today .. same weekday next week for the first strictly-future match.
        repeat(8) {
            if (candidate.timeInMillis > afterMillis && isoDays.contains(isoWeekday(candidate.get(Calendar.DAY_OF_WEEK)))) {
                return candidate.timeInMillis
            }
            candidate.add(Calendar.DAY_OF_YEAR, 1)
        }
        return null
    }
}
