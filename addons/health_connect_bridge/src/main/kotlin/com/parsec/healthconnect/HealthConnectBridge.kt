package com.parsec.healthconnect

import android.content.Intent
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.time.TimeRangeFilter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

class HealthConnectBridge(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val PERM_REQUEST_CODE = 1001
        private val PERMISSIONS = setOf(
            HealthPermission.getReadPermission(StepsRecord::class)
        )
    }

    override fun getPluginName() = "HealthConnectBridge"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("steps_ready", Int::class.javaObjectType),
        SignalInfo("health_unavailable")
    )

    // Called from GDScript as `request_and_fetch()`.
    // If permissions are already granted, queries today's steps immediately.
    // If not, opens the Health Connect permission dialog; re-call after the
    // user returns to the app and grants access.
    @UsedByGodot
    fun requestAndFetch() {
        val ctx = activity ?: run { emitSignal("health_unavailable"); return }

        if (HealthConnectClient.getSdkStatus(ctx) != HealthConnectClient.SDK_AVAILABLE) {
            emitSignal("health_unavailable")
            return
        }

        val client = HealthConnectClient.getOrCreate(ctx)
        CoroutineScope(Dispatchers.Main).launch {
            val granted = client.permissionController.getGrantedPermissions()
            if (PERMISSIONS.all { it in granted }) {
                querySteps(client)
            } else {
                val intent = PermissionController
                    .createRequestPermissionResultContract()
                    .createIntent(ctx, PERMISSIONS)
                ctx.startActivityForResult(intent, PERM_REQUEST_CODE)
            }
        }
    }

    // Godot calls this when the permission dialog returns.
    override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PERM_REQUEST_CODE) return
        val ctx = activity ?: run { emitSignal("health_unavailable"); return }
        val client = HealthConnectClient.getOrCreate(ctx)
        CoroutineScope(Dispatchers.Main).launch {
            val granted = client.permissionController.getGrantedPermissions()
            if (PERMISSIONS.all { it in granted }) querySteps(client)
            else emitSignal("health_unavailable")
        }
    }

    private suspend fun querySteps(client: HealthConnectClient) {
        try {
            val zone       = ZoneId.systemDefault()
            val startOfDay = LocalDate.now().atStartOfDay(zone).toInstant()
            val response   = client.aggregate(
                AggregateRequest(
                    metrics         = setOf(StepsRecord.COUNT_TOTAL),
                    timeRangeFilter = TimeRangeFilter.between(startOfDay, Instant.now())
                )
            )
            emitSignal("steps_ready", (response[StepsRecord.COUNT_TOTAL] ?: 0L).toInt())
        } catch (e: Exception) {
            emitSignal("health_unavailable")
        }
    }
}
