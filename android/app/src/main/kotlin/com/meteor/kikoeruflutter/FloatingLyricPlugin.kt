package com.meteor.kikoeruflutter

import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.WindowManager
import android.widget.TextView
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * 悬浮字幕插件
 * 负责管理悬浮窗的显示、隐藏和更新
 */
class FloatingLyricPlugin private constructor(private val context: Context) : MethodCallHandler {
    companion object {
        const val CHANNEL = "com.kikoeru.flutter/floating_lyric"
        
        @Volatile
        private var instance: FloatingLyricPlugin? = null

        fun getInstance(context: Context): FloatingLyricPlugin {
            return instance ?: synchronized(this) {
                instance ?: FloatingLyricPlugin(context.applicationContext).also { instance = it }
            }
        }
    }

    private var windowManager: WindowManager? = null
    private var floatingView: FloatingLyricView? = null
    private var isShowing = false

    init {
        windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "show" -> {
                val text = call.argument<String>("text") ?: "♪ - ♪"
                show(text, result)
            }
            "hide" -> {
                hide(result)
            }
            "updateText" -> {
                val text = call.argument<String>("text") ?: ""
                updateText(text, result)
            }
            "hasPermission" -> {
                result.success(hasPermission())
            }
            "requestPermission" -> {
                requestPermission(result)
            }
            "updateStyle" -> {
                updateStyle(call, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun show(text: String, result: Result) {
        if (!hasPermission()) {
            result.error("NO_PERMISSION", "没有悬浮窗权限", null)
            return
        }

        try {
            if (isShowing) {
                // 如果已经显示，只更新文本
                floatingView?.updateText(text)
                result.success(true)
                return
            }

            // 配置窗口参数
            val params = WindowManager.LayoutParams().apply {
                width = WindowManager.LayoutParams.WRAP_CONTENT
                height = WindowManager.LayoutParams.WRAP_CONTENT
                type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_PHONE
                }
                // 移除 FLAG_NOT_FOCUSABLE，改为 FLAG_NOT_TOUCH_MODAL 以支持触摸事件
                flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                format = PixelFormat.TRANSLUCENT
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                x = 0 // 水平居中
                y = 100 // 距离顶部的距离
            }

            // 创建悬浮窗视图（传入 windowManager 和 params 以支持拖动）
            floatingView = FloatingLyricView(context, windowManager!!, params)
            floatingView?.updateText(text)

            // 添加到窗口
            windowManager?.addView(floatingView as android.view.View, params)
            isShowing = true
            result.success(true)
        } catch (e: Exception) {
            result.error("SHOW_FAILED", "显示悬浮窗失败: ${e.message}", null)
        }
    }

    private fun hide(result: Result) {
        try {
            if (isShowing && floatingView != null) {
                windowManager?.removeView(floatingView as android.view.View)
                floatingView = null
                isShowing = false
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("HIDE_FAILED", "隐藏悬浮窗失败: ${e.message}", null)
        }
    }

    private fun updateText(text: String, result: Result) {
        try {
            if (isShowing && floatingView != null) {
                floatingView?.updateText(text)
                result.success(true)
            } else {
                result.success(false)
            }
        } catch (e: Exception) {
            result.error("UPDATE_FAILED", "更新文本失败: ${e.message}", null)
        }
    }

    private fun hasPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    private fun requestPermission(result: Result) {
        if (hasPermission()) {
            result.success(true)
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${context.packageName}")
                ).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
                result.success(false) // 返回 false 表示需要用户手动授权
            } else {
                result.success(true)
            }
        } catch (e: Exception) {
            result.error("REQUEST_FAILED", "请求权限失败: ${e.message}", null)
        }
    }

    private fun updateStyle(call: MethodCall, result: Result) {
        try {
            val fontSize = call.argument<Double>("fontSize")
            // Dart int is 64-bit, so it might be passed as Long
            val textColor = call.argument<Number>("textColor")?.toInt()
            val backgroundColor = call.argument<Number>("backgroundColor")?.toInt()
            val cornerRadius = call.argument<Double>("cornerRadius")
            val paddingHorizontal = call.argument<Double>("paddingHorizontal")
            val paddingVertical = call.argument<Double>("paddingVertical")

            floatingView?.updateStyle(
                fontSize?.toFloat(),
                textColor,
                backgroundColor,
                cornerRadius?.toFloat(),
                paddingHorizontal?.toFloat(),
                paddingVertical?.toFloat()
            )
            result.success(true)
        } catch (e: Exception) {
            result.error("UPDATE_STYLE_FAILED", "更新样式失败: ${e.message}", null)
        }
    }

    /**
     * 清理资源
     */
    fun cleanup() {
        if (isShowing) {
            try {
                windowManager?.removeView(floatingView as android.view.View)
            } catch (e: Exception) {
                // 忽略错误
            }
            floatingView = null
            isShowing = false
        }
    }
}
