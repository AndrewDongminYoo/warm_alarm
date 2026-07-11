package com.andrew.alarm

import java.util.Calendar
import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WarmAlarmRecurrenceTest {
    private val utc = TimeZone.getTimeZone("UTC")

    /** Builds an epoch-millis timestamp in [utc] for the given wall-clock. */
    private fun millis(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        tz: TimeZone = utc,
    ): Long =
        Calendar
            .getInstance(tz)
            .apply {
                clear()
                set(year, month - 1, day, hour, minute, 0)
            }.timeInMillis

    private fun isoWeekdayOf(
        m: Long,
        tz: TimeZone = utc,
    ): Int {
        val dow = Calendar.getInstance(tz).apply { timeInMillis = m }.get(Calendar.DAY_OF_WEEK)
        return if (dow == Calendar.SUNDAY) 7 else dow - 1
    }

    @Test
    fun emptyWeekdaysReturnsNull() {
        assertNull(WarmAlarmRecurrence.nextOccurrence(0, emptyList(), 0, utc))
    }

    @Test
    fun laterSameDayIsChosenWhenTimeHasNotPassed() {
        // 2026-01-05 is a Monday (ISO 1). Base time 09:00, "now" 07:00 same day.
        val base = millis(2026, 1, 5, 9, 0)
        val now = millis(2026, 1, 5, 7, 0)
        val next = WarmAlarmRecurrence.nextOccurrence(base, listOf(1), now, utc)!!
        assertEquals(millis(2026, 1, 5, 9, 0), next)
    }

    @Test
    fun todayAlreadyPassedRollsToNextWeek() {
        // Monday base 09:00, now Monday 10:00 (already passed) -> next Monday.
        val base = millis(2026, 1, 5, 9, 0)
        val now = millis(2026, 1, 5, 10, 0)
        val next = WarmAlarmRecurrence.nextOccurrence(base, listOf(1), now, utc)!!
        assertEquals(millis(2026, 1, 12, 9, 0), next)
        assertEquals(1, isoWeekdayOf(next))
    }

    @Test
    fun sundayWraparoundMapsCorrectly() {
        // ISO 7 = Sunday. 2026-01-05 is Monday; next Sunday is 2026-01-11.
        val base = millis(2026, 1, 5, 6, 30)
        val now = millis(2026, 1, 5, 6, 30)
        val next = WarmAlarmRecurrence.nextOccurrence(base, listOf(7), now, utc)!!
        assertEquals(7, isoWeekdayOf(next))
        assertEquals(millis(2026, 1, 11, 6, 30), next)
    }

    @Test
    fun picksNearestOfMultipleWeekdays() {
        // Weekdays Mon(1) + Wed(3) + Fri(5); now Tuesday -> next is Wednesday.
        val base = millis(2026, 1, 5, 8, 0) // Monday
        val now = millis(2026, 1, 6, 12, 0) // Tuesday
        val next = WarmAlarmRecurrence.nextOccurrence(base, listOf(1, 3, 5), now, utc)!!
        assertEquals(3, isoWeekdayOf(next))
        assertEquals(millis(2026, 1, 7, 8, 0), next)
    }

    @Test
    fun allSevenDaysYieldsTomorrowWhenTodayPassed() {
        val base = millis(2026, 1, 5, 9, 0)
        val now = millis(2026, 1, 5, 23, 0)
        val next = WarmAlarmRecurrence.nextOccurrence(base, listOf(1, 2, 3, 4, 5, 6, 7), now, utc)!!
        assertEquals(millis(2026, 1, 6, 9, 0), next)
    }

    @Test
    fun resultIsAlwaysStrictlyAfterNow() {
        val base = millis(2026, 3, 2, 7, 15)
        val now = millis(2026, 3, 2, 7, 15) // exactly equal to base time-of-day today (Monday)
        val next = WarmAlarmRecurrence.nextOccurrence(base, listOf(1), now, utc)!!
        assertTrue(next > now)
        assertEquals(millis(2026, 3, 9, 7, 15), next)
    }

    @Test
    fun survivesDstSpringForwardBoundary() {
        // US Eastern DST begins 2026-03-08 (Sunday) 02:00 -> 03:00.
        val eastern = TimeZone.getTimeZone("America/New_York")
        val base = millis(2026, 3, 1, 6, 30, eastern) // Sunday 06:30 local
        val now = millis(2026, 3, 1, 7, 0, eastern) // just after, same Sunday
        val next = WarmAlarmRecurrence.nextOccurrence(base, listOf(7), now, eastern)!!
        // Next Sunday spans the spring-forward transition; time-of-day must stay 06:30.
        val cal = Calendar.getInstance(eastern).apply { timeInMillis = next }
        assertEquals(6, cal.get(Calendar.HOUR_OF_DAY))
        assertEquals(30, cal.get(Calendar.MINUTE))
        assertEquals(7, isoWeekdayOf(next, eastern))
    }
}
