package com.honghong.honghong

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 桌面小部件和下拉快捷开关（设计稿 17）。
 * 数据由 Dart 侧 QuickSurfaces.publish 写进 home_widget 的 SharedPreferences；
 * 按钮发 honghong://quick?a=<动作> 给 home_widget 的后台回调，由 Dart 的 runQuickAction 执行（和锁屏通知同一套逻辑）。
 */
object HhQuick {
    private val labels = mapOf("feed" to "喂奶", "sleep" to "睡觉", "burp" to "拍嗝")

    fun action(context: Context, id: String): PendingIntent =
        HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("honghong://quick?a=$id"))

    fun send(context: Context, id: String) {
        // 直接发广播（快捷开关里用），和 PendingIntent 走同一个接收器
        val intent = Intent(context, es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java)
        intent.data = Uri.parse("honghong://quick?a=$id")
        intent.action = "es.antonborri.home_widget.action.BACKGROUND"
        context.sendBroadcast(intent)
    }

    fun openApp(context: Context): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("honghong://home"))

    fun start(p: SharedPreferences, type: String): Long = readLong(p, "hh_${type}_start")

    /** home_widget 存 int/long 都可能，统一读成 Long */
    fun readLong(p: SharedPreferences, key: String): Long = when (val v = p.all[key]) {
        is Long -> v
        is Int -> v.toLong()
        is String -> v.toLongOrNull() ?: 0L
        else -> 0L
    }

    fun str(p: SharedPreferences, key: String): String = p.getString(key, "") ?: ""

    /** 头部：标题、副标题、计时器 */
    fun bindHeader(views: RemoteViews, p: SharedPreferences, withSub: Boolean) {
        val runType = str(p, "hh_run_type")
        val runStart = readLong(p, "hh_run_start")
        val done = str(p, "hh_done")
        val baby = str(p, "hh_baby").ifEmpty { "宝宝" }
        if (runType.isNotEmpty() && runStart > 0) {
            views.setTextViewText(R.id.title, str(p, "hh_run_label"))
            views.setImageViewResource(R.id.head_icon, iconFor(runType))
            val base = SystemClock.elapsedRealtime() - (System.currentTimeMillis() - runStart)
            views.setChronometer(R.id.chrono, base, null, true)
            views.setViewVisibility(R.id.chrono, View.VISIBLE)
        } else {
            views.setTextViewText(R.id.title, if (done.isNotEmpty() && !withSub) done else baby)
            views.setImageViewResource(R.id.head_icon, R.drawable.hh_avatar_baby)
            views.setChronometer(R.id.chrono, SystemClock.elapsedRealtime(), null, false)
            views.setViewVisibility(R.id.chrono, View.GONE)
        }
        if (withSub) {
            views.setTextViewText(R.id.sub, if (done.isNotEmpty() && runType.isEmpty()) done else str(p, "hh_sub"))
        }
    }

    fun iconFor(type: String) = when (type) {
        "feed" -> R.drawable.hh_care_feed
        "sleep" -> R.drawable.hh_care_sleep
        "burp" -> R.drawable.hh_care_burp
        else -> R.drawable.hh_care_diaper
    }

    fun buildLarge(context: Context, p: SharedPreferences): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.hh_widget)
        bindHeader(v, p, withSub = true)
        val ids = mapOf(
            "feed" to Triple(R.id.btn_feed, R.id.txt_feed, R.id.img_feed),
            "sleep" to Triple(R.id.btn_sleep, R.id.txt_sleep, R.id.img_sleep),
            "burp" to Triple(R.id.btn_burp, R.id.txt_burp, R.id.img_burp),
        )
        for ((type, id) in ids) {
            val running = start(p, type) > 0
            v.setTextViewText(id.second, (if (running) "结束" else "开始") + labels[type])
            v.setTextColor(id.second, if (running) 0xFFFFFFFF.toInt() else 0xFF3D3A45.toInt())
            v.setInt(id.first, "setBackgroundResource", if (running) R.drawable.hh_btn_on else R.drawable.hh_btn)
            v.setOnClickPendingIntent(id.first, action(context, (if (running) "end:" else "start:") + type))
        }
        v.setTextViewText(R.id.txt_diaper, "换尿布")
        v.setOnClickPendingIntent(R.id.btn_diaper, action(context, "diaper"))
        v.setOnClickPendingIntent(R.id.root, openApp(context))
        v.setOnClickPendingIntent(R.id.header, openApp(context))
        return v
    }

    fun buildSmall(context: Context, p: SharedPreferences): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.hh_widget_small)
        bindHeader(v, p, withSub = false)
        val runType = str(p, "hh_run_type")
        val running = runType.isNotEmpty()
        v.setTextViewText(R.id.btn_main, if (running) "结束" + labels[runType] else "开始喂奶")
        v.setTextColor(R.id.btn_main, if (running) 0xFFFFFFFF.toInt() else 0xFF3D3A45.toInt())
        v.setInt(R.id.btn_main, "setBackgroundResource", if (running) R.drawable.hh_btn_on else R.drawable.hh_btn)
        v.setOnClickPendingIntent(R.id.btn_main, action(context, if (running) "end:$runType" else "start:feed"))
        v.setOnClickPendingIntent(R.id.btn_diaper, action(context, "diaper"))
        v.setOnClickPendingIntent(R.id.root, openApp(context))
        v.setOnClickPendingIntent(R.id.header, openApp(context))
        return v
    }

    /** 让三个快捷开关重新读取状态 */
    fun refreshTiles(context: Context) {
        for (c in listOf(FeedTileService::class.java, SleepTileService::class.java, DiaperTileService::class.java)) {
            try {
                TileService.requestListeningState(context, ComponentName(context, c))
            } catch (_: Exception) {
            }
        }
    }
}

abstract class BaseQuickWidget : HomeWidgetProvider() {
    abstract fun build(context: Context, p: SharedPreferences): RemoteViews

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, build(context, widgetData))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // 没放小部件时 Dart 的 updateWidget 也会到这里：顺便刷新快捷开关
        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) HhQuick.refreshTiles(context)
    }
}

class QuickWidgetProvider : BaseQuickWidget() {
    override fun build(context: Context, p: SharedPreferences) = HhQuick.buildLarge(context, p)
}

class QuickWidgetSmallProvider : BaseQuickWidget() {
    override fun build(context: Context, p: SharedPreferences) = HhQuick.buildSmall(context, p)
}

/** 喂奶 / 睡觉：开关型。亮起 = 正在计时，点一下 开始 ↔ 结束 */
abstract class SessionTileService(private val type: String, private val label: String) : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        render(HomeWidgetPlugin.getData(this))
    }

    private fun render(p: SharedPreferences, runningOverride: Boolean? = null) {
        val tile = qsTile ?: return
        val start = HhQuick.start(p, type)
        val running = runningOverride ?: (start > 0)
        tile.label = label
        tile.state = if (running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= 29) {
            tile.subtitle = when {
                runningOverride == true -> "刚刚开始"
                runningOverride == false -> "已结束"
                running -> hm(start) + " 开始"
                type == "sleep" && HhQuick.str(p, "hh_sleep_woke").isNotEmpty() -> HhQuick.str(p, "hh_sleep_woke") + " 醒"
                type == "feed" && HhQuick.str(p, "hh_feed_last").isNotEmpty() -> "上次 " + HhQuick.str(p, "hh_feed_last")
                else -> "点一下开始"
            }
        }
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        val running = HhQuick.start(HomeWidgetPlugin.getData(this), type) > 0
        HhQuick.send(this, (if (running) "end:" else "start:") + type)
        render(HomeWidgetPlugin.getData(this), runningOverride = !running) // 先乐观更新，Dart 写完后会再刷新
    }
}

class FeedTileService : SessionTileService("feed", "喂奶")
class SleepTileService : SessionTileService("sleep", "睡觉")

/** 换尿布：一次性，点一下记一条 */
class DiaperTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile ?: return
        val last = HhQuick.str(HomeWidgetPlugin.getData(this), "hh_diaper_last")
        tile.label = "换尿布"
        tile.state = Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= 29) tile.subtitle = if (last.isEmpty()) "点一下记一条" else "上次 $last"
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        HhQuick.send(this, "diaper")
        val tile = qsTile ?: return
        if (Build.VERSION.SDK_INT >= 29) tile.subtitle = "已记下 " + hm(System.currentTimeMillis())
        tile.updateTile()
    }
}

private fun hm(ms: Long): String {
    val c = java.util.Calendar.getInstance().apply { timeInMillis = ms }
    return String.format("%02d:%02d", c.get(java.util.Calendar.HOUR_OF_DAY), c.get(java.util.Calendar.MINUTE))
}
