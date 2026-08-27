package com.andrew.alarm

import android.content.Context
import android.os.Build
import android.os.UserManager

internal object WarmAlarmDirectBoot {
    fun storageContext(context: Context): Context = if (isLocked(context)) context.createDeviceProtectedStorageContext() else context

    fun canReadCredentialProtectedFiles(context: Context): Boolean = !isLocked(context)

    private fun isLocked(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val userManager = context.getSystemService(Context.USER_SERVICE) as? UserManager ?: return false
        return !userManager.isUserUnlocked
    }
}
