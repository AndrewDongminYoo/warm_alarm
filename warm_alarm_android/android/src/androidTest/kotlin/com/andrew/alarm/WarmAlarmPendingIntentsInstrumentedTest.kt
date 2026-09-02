package com.andrew.alarm

import android.app.PendingIntent
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/**
 * The claim [WarmAlarmPendingIntentsTest] cannot make.
 *
 * AlarmManager looks a PendingIntent up by request code plus [android.content.Intent.filterEquals],
 * and filterEquals ignores extras. Both kinds here carry request code `alarmId`, so the data Uri is
 * the only thing that can separate them, and only the framework's own registry can say whether it
 * does. The JVM tests assert the identity this plugin asks for; these assert that Android agrees.
 *
 * Both tests fail if [WarmAlarmPendingIntents.identityUri] goes back to returning null for
 * [WarmAlarmIntentKind.RETRIGGER], which is the pre-0.1.2 shape.
 */
class WarmAlarmPendingIntentsInstrumentedTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    // Well outside the ids any other test or the example app schedules, so a leaked
    // registration cannot make this pass or fail for the wrong reason.
    private val alarmId = 987_654L

    @Before
    fun clearBefore() = clearRegistry()

    @After
    fun clearAfter() = clearRegistry()

    private fun clearRegistry() {
        for (kind in WarmAlarmIntentKind.entries) {
            lookUp(kind)?.cancel()
        }
    }

    private fun lookUp(kind: WarmAlarmIntentKind): PendingIntent? =
        WarmAlarmPendingIntents.broadcast(context, alarmId, kind, PendingIntent.FLAG_NO_CREATE)

    private fun register(kind: WarmAlarmIntentKind): PendingIntent? =
        WarmAlarmPendingIntents.broadcast(context, alarmId, kind, PendingIntent.FLAG_UPDATE_CURRENT)

    @Test
    fun aRegisteredRegularAlarmDoesNotAnswerARetriggerLookup() {
        assertNotNull(register(WarmAlarmIntentKind.REGULAR))

        // Before 0.1.2 this lookup returned the regular alarm's own handle, so arming a
        // retrigger re-targeted the recurring alarm's pending next occurrence.
        assertNull(lookUp(WarmAlarmIntentKind.RETRIGGER))
    }

    @Test
    fun cancellingARetriggerLeavesTheRegularAlarmRegistered() {
        assertNotNull(register(WarmAlarmIntentKind.REGULAR))
        val retrigger = register(WarmAlarmIntentKind.RETRIGGER)
        assertNotNull(retrigger)

        retrigger!!.cancel()

        assertNull(lookUp(WarmAlarmIntentKind.RETRIGGER))
        // Before 0.1.2 the two were one handle, so ending a wake-check cycle cancelled the
        // series along with the retrigger. That is the success path, not a failure path.
        assertNotNull(lookUp(WarmAlarmIntentKind.REGULAR))
    }
}
